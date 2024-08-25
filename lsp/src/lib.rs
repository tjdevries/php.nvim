use std::collections::HashMap;

use anyhow::Result;
use tower_lsp::lsp_types::Position;
use tracing::info;
use tree_sitter::{Language, Node, Parser, Point, Query, QueryCursor, Tree};

mod injection;

pub struct LanguageConfiguration {
    pub language_name: String,
    pub language: Language,
    pub injection_query: Query,
    pub injection_content_capture_index: Option<u32>,
    pub injection_language_capture_index: Option<u32>,
}

impl LanguageConfiguration {
    pub fn new(name: String, language: Language, injection_query: &str) -> Result<Self> {
        let query = Query::new(language, injection_query)?;

        let mut injection_content_index = None;
        let mut injection_language_index = None;
        for (i, name) in query.capture_names().iter().enumerate() {
            let i = Some(i as u32);
            match name.as_str() {
                "injection.content" => injection_content_index = i,
                "injection.language" => injection_language_index = i,
                _ => {}
            }
        }

        Ok(Self {
            language_name: name,
            language,
            injection_query: query,
            injection_content_capture_index: injection_content_index,
            injection_language_capture_index: injection_language_index,
        })
    }

    pub fn parser(&self) -> Result<Parser> {
        let mut parser = Parser::new();
        parser.set_language(self.language)?;

        Ok(parser)
    }

    pub fn blade() -> Self {
        Self::new(
            "blade".to_string(),
            tree_sitter_blade::language(),
            include_str!("../../queries/blade/injections.scm"),
        )
        .expect("blade query")
    }

    pub fn php() -> Self {
        Self::new(
            "php".to_string(),
            tree_sitter_php::language_php(),
            tree_sitter_php::INJECTIONS_QUERY,
        )
        .expect("php query")
    }

    pub fn php_only() -> Self {
        Self::new(
            "php_only".to_string(),
            tree_sitter_php::language_php_only(),
            tree_sitter_php::INJECTIONS_QUERY,
        )
        .expect("php query")
    }

    pub fn html() -> Self {
        Self::new(
            "html".to_string(),
            tree_sitter_html::language(),
            tree_sitter_html::INJECTIONS_QUERY,
        )
        .expect("html")
    }

    pub fn to_language(name: &str) -> Option<Self> {
        match name {
            "blade" => Some(Self::blade()),
            "html" => Some(Self::html()),
            "php" => Some(Self::php()),
            "php_only" => Some(Self::php_only()),
            _ => None,
        }
    }
}

pub struct LanguageTree {
    pub source: String,
    pub config: LanguageConfiguration,
    pub children: HashMap<String, LanguageTree>,
}

impl LanguageTree {
    pub fn new(config: LanguageConfiguration, source: &str) -> Result<Self> {
        // TODO: This should probably parse
        Ok(Self {
            source: source.to_string(),
            config,
            children: HashMap::default(),
        })
    }

    pub fn descendant_for_point_range<'a>(
        &self,
        tree: &'a Tree,
        start: Point,
        end: Point,
    ) -> Option<Position> {
        let mut parser = Parser::new();
        parser.set_language(self.config.language).ok()?;

        let query = &self.config.injection_query;

        let mut cursor = QueryCursor::new();
        let matches = cursor.matches(query, tree.root_node(), self.source.as_bytes());
        for m in matches {
            if m.pattern_index == 0 {
                info!("php match: {:?}", m);
                let mut html_parser = Parser::new();
                html_parser
                    .set_language(tree_sitter_html::language())
                    .expect("html");

                let node = m
                    .nodes_for_capture_index(0)
                    .next()
                    .expect("to match something");
                let html_text = node.utf8_text(self.source.as_bytes()).expect("text");
                let html_tree = html_parser.parse(html_text, None).expect("html");
                let html_root =
                    html_tree.root_node_with_offset(node.start_byte(), node.start_position());

                print_node(html_root, 0);
                if let Some(node) = html_root.descendant_for_point_range(start, end) {
                    // bad hack
                    if node.start_byte() != 0 {
                        return Some(point_to_position(&node.start_position()));
                    }
                }
            }
            // m.nodes_for_capture_index(capture_ix)
        }

        tree.root_node()
            .descendant_for_point_range(start, end)
            .map(|node| point_to_position(&node.start_position()))
    }

    pub fn parent_with_name<'a>(
        &self,
        tree: &'a Tree,
        name: &str,
        start: Point,
        end: Point,
    ) -> Option<Position> {
        let mut parser = Parser::new();
        parser.set_language(self.config.language).ok()?;

        let query = &self.config.injection_query;

        let mut cursor = QueryCursor::new();
        let matches = cursor.matches(query, tree.root_node(), self.source.as_bytes());
        for m in matches {
            if m.pattern_index == 0 {
                info!("php match: {:?}", m);
                let mut html_parser = Parser::new();
                html_parser
                    .set_language(tree_sitter_php::language_php())
                    .expect("php");

                let node = m
                    .nodes_for_capture_index(0)
                    .next()
                    .expect("to match something");
                let html_text = node.utf8_text(self.source.as_bytes()).expect("text");
                let html_tree = html_parser.parse(html_text, None).expect("html");
                let html_root =
                    html_tree.root_node_with_offset(node.start_byte(), node.start_position());

                print_node(html_root, 0);
                if let Some(child_node) = html_root.descendant_for_point_range(start, end) {
                    // bad hack
                    if child_node.start_byte() != 0 {
                        let mut child_node = child_node;
                        info!(
                            "STARTING WALKING WITH: {:?} => {:?}",
                            child_node,
                            child_node.kind()
                        );

                        while child_node.kind() != name {
                            match child_node.parent() {
                                Some(parent) => {
                                    info!("PARENT: {:?}", parent);
                                    child_node = parent;
                                }
                                None => break,
                            }
                        }

                        let start = child_node.start_position();
                        // start.row += node.start_position().row;
                        // start.column += node.start_position().column;
                        return Some(point_to_position(&start));
                    }
                }
            }
            // m.nodes_for_capture_index(capture_ix)
        }

        tree.root_node()
            .descendant_for_point_range(start, end)
            .map(|node| point_to_position(&node.start_position()))
    }
}

pub fn point_to_position(point: &Point) -> Position {
    Position {
        line: point.row as u32,
        character: point.column as u32,
    }
}

pub fn print_node(node: Node, level: usize) {
    let indent = " ".repeat(level * 2);
    info!("{}Node: {:?}", indent, node);
    let mut cursor = node.walk();

    if !node.is_named() {
        return;
    }

    for child in node.children(&mut cursor) {
        print_node(child, level + 1);
    }
}

#[cfg(test)]
mod test {
    use super::*;

    #[test]
    fn test_can_parse_some_blade() -> Result<()> {
        let source = r#"
<x-app-layout>
    <x-slot name="header">
        <h2 class="font-semibold text-xl text-gray-800 dark:text-gray-200 leading-tight">
            {{ __('Profile') }}
        </h2>
    </x-slot>
</x-app-layout>
"#;

        let config = LanguageConfiguration::blade();
        let tree = LanguageTree::new(config, source)?;

        Ok(())
    }
}
