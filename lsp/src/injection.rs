use tree_sitter::{Node, Query, QueryMatch};

use crate::LanguageConfiguration;

fn injection_for_match<'a>(
    config: &'a LanguageConfiguration,
    parent_name: Option<&'a str>,
    query: &'a Query,
    query_match: &QueryMatch<'a, 'a>,
    source: &'a [u8],
) -> (Option<&'a str>, Option<Node<'a>>, bool) {
    let content_capture_index = config.injection_content_capture_index;
    let language_capture_index = config.injection_language_capture_index;

    let mut language_name = None;
    let mut content_node = None;

    for capture in query_match.captures {
        let index = Some(capture.index);
        if index == language_capture_index {
            language_name = capture.node.utf8_text(source).ok();
        } else if index == content_capture_index {
            content_node = Some(capture.node);
        }
    }

    let mut include_children = false;
    for prop in query.property_settings(query_match.pattern_index) {
        match prop.key.as_ref() {
            // In addition to specifying the language name via the text of a
            // captured node, it can also be hard-coded via a `#set!` predicate
            // that sets the injection.language key.
            "injection.language" => {
                if language_name.is_none() {
                    language_name = prop.value.as_ref().map(|s| s.as_ref());
                }
            }

            // Setting the `injection.self` key can be used to specify that the
            // language name should be the same as the language of the current
            // layer.
            "injection.self" => {
                if language_name.is_none() {
                    language_name = Some(config.language_name.as_str());
                }
            }

            // Setting the `injection.parent` key can be used to specify that
            // the language name should be the same as the language of the
            // parent layer
            "injection.parent" => {
                if language_name.is_none() {
                    language_name = parent_name;
                }
            }

            // By default, injections do not include the *children* of an
            // `injection.content` node - only the ranges that belong to the
            // node itself. This can be changed using a `#set!` predicate that
            // sets the `injection.include-children` key.
            "injection.include-children" => include_children = true,
            _ => {}
        }
    }

    (language_name, content_node, include_children)
}
