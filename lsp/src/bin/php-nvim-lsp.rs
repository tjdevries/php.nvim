use std::io::BufWriter;

use dashmap::DashMap;
use lsp::{LanguageConfiguration, LanguageTree};
use serde_json::Value;
use tower_lsp::jsonrpc::Result;
use tower_lsp::lsp_types::*;
use tower_lsp::{Client, LanguageServer, LspService, Server};
use tracing::info;
use tracing_subscriber::filter::LevelFilter;

#[derive(Debug)]
struct Backend {
    client: Client,
    documents: dashmap::DashMap<Url, String>,
}

#[tower_lsp::async_trait]
impl LanguageServer for Backend {
    async fn initialize(&self, _: InitializeParams) -> Result<InitializeResult> {
        Ok(InitializeResult {
            server_info: None,
            capabilities: ServerCapabilities {
                text_document_sync: Some(TextDocumentSyncCapability::Kind(
                    TextDocumentSyncKind::FULL,
                )),
                completion_provider: Some(CompletionOptions {
                    resolve_provider: Some(false),
                    trigger_characters: Some(vec!["->".to_string()]),
                    work_done_progress_options: Default::default(),
                    all_commit_characters: None,
                    ..Default::default()
                }),
                execute_command_provider: Some(ExecuteCommandOptions {
                    commands: vec!["dummy.do_something".to_string()],
                    work_done_progress_options: Default::default(),
                }),
                workspace: Some(WorkspaceServerCapabilities {
                    workspace_folders: Some(WorkspaceFoldersServerCapabilities {
                        supported: Some(true),
                        change_notifications: Some(OneOf::Left(true)),
                    }),
                    file_operations: None,
                }),
                definition_provider: Some(OneOf::Left(true)),
                ..ServerCapabilities::default()
            },
            ..Default::default()
        })
    }

    async fn initialized(&self, _: InitializedParams) {
        self.client
            .log_message(MessageType::INFO, "initialized!")
            .await;
    }

    async fn shutdown(&self) -> Result<()> {
        Ok(())
    }

    async fn did_change_workspace_folders(&self, _: DidChangeWorkspaceFoldersParams) {
        self.client
            .log_message(MessageType::INFO, "workspace folders changed!")
            .await;
    }

    async fn did_change_configuration(&self, _: DidChangeConfigurationParams) {
        self.client
            .log_message(MessageType::INFO, "configuration changed!")
            .await;
    }

    async fn did_change_watched_files(&self, _: DidChangeWatchedFilesParams) {
        self.client
            .log_message(MessageType::INFO, "watched files have changed!")
            .await;
    }

    async fn execute_command(&self, _: ExecuteCommandParams) -> Result<Option<Value>> {
        self.client
            .log_message(MessageType::INFO, "command executed!")
            .await;

        match self.client.apply_edit(WorkspaceEdit::default()).await {
            Ok(res) if res.applied => self.client.log_message(MessageType::INFO, "applied").await,
            Ok(_) => self.client.log_message(MessageType::INFO, "rejected").await,
            Err(err) => self.client.log_message(MessageType::ERROR, err).await,
        }

        Ok(None)
    }

    async fn did_open(&self, open: DidOpenTextDocumentParams) {
        let TextDocumentItem { uri, text, .. } = open.text_document;

        info!("textDocument/didOpen: {:?}", uri.to_file_path());
        self.documents.insert(uri, text);
    }

    async fn did_change(&self, change: DidChangeTextDocumentParams) {
        info!("textDocument/didChange");

        let changes = change.content_changes;
        if changes.len() != 1 {
            panic!("Yo cannot have more than one {:?}", changes);
        }
        let text = changes[0].text.clone();
        self.documents.insert(change.text_document.uri, text);

        self.client
            .log_message(MessageType::INFO, "file changed!")
            .await;
    }

    async fn did_save(&self, _: DidSaveTextDocumentParams) {
        self.client
            .log_message(MessageType::INFO, "file saved!")
            .await;
    }

    async fn did_close(&self, _: DidCloseTextDocumentParams) {
        self.client
            .log_message(MessageType::INFO, "file closed!")
            .await;
    }

    async fn completion(&self, _: CompletionParams) -> Result<Option<CompletionResponse>> {
        Ok(Some(CompletionResponse::Array(vec![
            CompletionItem::new_simple("Hello".to_string(), "Some detail".to_string()),
            CompletionItem::new_simple("Bye".to_string(), "More detail".to_string()),
        ])))
    }

    async fn goto_definition(
        &self,
        params: GotoDefinitionParams,
    ) -> Result<Option<GotoDefinitionResponse>> {
        info!("textDocument/gotoDefinition {:?}", params);

        let TextDocumentPositionParams {
            position,
            text_document,
        } = params.text_document_position_params;

        let text = self
            .documents
            .get(&text_document.uri)
            .ok_or(tower_lsp::jsonrpc::Error::invalid_request())?;

        let config = LanguageConfiguration::blade();
        let mut parser = config.parser().expect("parser");

        let tree = parser
            .parse(text.as_bytes(), None)
            .ok_or(tower_lsp::jsonrpc::Error::invalid_request())?;

        let langtree = LanguageTree::new(config, &text).expect("to parse lang tree");
        let point = ts::position_to_point(&position);
        let start = langtree
            // .descendant_for_point_range(&tree, point, point)
            .parent_with_name(&tree, "element", point, point)
            .expect("to find a node");

        // info!("  tree: {:?}", tree.root_node());
        // let _ = ts::print_node(tree.root_node(), 0);
        //
        //
        // let node = ts::get_node_at_point(&tree, point)
        //     .ok_or(tower_lsp::jsonrpc::Error::invalid_request())?;
        // info!("  node: {:?}", node);

        // let start = node.start_position();

        Ok(Some(GotoDefinitionResponse::Scalar(Location {
            uri: text_document.uri,
            range: Range {
                start: start.clone(),
                end: start,
            },
        })))
    }
}

mod ts {
    use super::*;
    use tower_lsp::lsp_types::Position;
    use tree_sitter::{Node, Point};

    pub fn position_to_point(position: &Position) -> Point {
        Point {
            row: position.line as usize,
            column: position.character as usize,
        }
    }

    pub fn point_to_position(point: &Point) -> Position {
        Position {
            line: point.row as u32,
            character: point.column as u32,
        }
    }

    pub fn get_node_at_point(tree: &tree_sitter::Tree, point: Point) -> Option<Node> {
        return tree.root_node().descendant_for_point_range(point, point);
    }
}

#[tokio::main]
async fn main() {
    let file = std::fs::File::create("/home/tjdevries/tmp/php-nvim-lsp.log").expect("to make file");
    let file = BufWriter::new(file);
    let (non_blocking, _guard) = tracing_appender::non_blocking(file);
    let subscriber = tracing_subscriber::fmt()
        .with_ansi(false)
        .with_max_level(LevelFilter::DEBUG)
        .with_writer(non_blocking)
        .finish();

    // Set the subscriber as the global default
    tracing::subscriber::set_global_default(subscriber).expect("setting default subscriber failed");

    info!("starting php-nvim-lsp");
    let (stdin, stdout) = (tokio::io::stdin(), tokio::io::stdout());
    let (service, socket) = LspService::new(|client| Backend {
        client,
        documents: DashMap::default(),
    });

    Server::new(stdin, stdout, socket).serve(service).await;
}
