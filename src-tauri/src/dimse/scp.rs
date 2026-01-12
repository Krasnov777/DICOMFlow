// DICOM Service Class Provider (SCP) - Receiving side

use super::DimseConfig;
use anyhow::Result;
use std::sync::Arc;
use tokio::sync::RwLock;

pub struct ScpServer {
    config: DimseConfig,
    running: Arc<RwLock<bool>>,
}

impl ScpServer {
    pub fn new(config: DimseConfig) -> Self {
        Self {
            config,
            running: Arc::new(RwLock::new(false)),
        }
    }

    /// Start the SCP listener
    pub async fn start(&self) -> Result<()> {
        use tokio::net::TcpListener;
        use dicom_ul::association::server::ServerAssociationOptions;

        let mut running = self.running.write().await;
        if *running {
            return Ok(());
        }

        *running = true;
        tracing::info!(
            "Starting SCP server '{}' on port {}",
            self.config.ae_title,
            self.config.port
        );

        // Spawn a background task to handle incoming connections
        let port = self.config.port;
        let ae_title = self.config.ae_title.clone();
        let running_clone = Arc::clone(&self.running);

        tokio::spawn(async move {
            // Bind TCP listener
            let addr = format!("0.0.0.0:{}", port);
            match TcpListener::bind(&addr).await {
                Ok(listener) => {
                    tracing::info!("SCP server listening on {}", addr);

                    // Accept incoming connections
                    while *running_clone.read().await {
                        match listener.accept().await {
                            Ok((stream, peer_addr)) => {
                                tracing::info!("Incoming DICOM association from {}", peer_addr);

                                // Spawn a task to handle this association
                                let ae_title_clone = ae_title.clone();
                                tokio::spawn(async move {
                                    if let Err(e) = handle_association(stream, ae_title_clone).await {
                                        tracing::error!("Error handling association: {}", e);
                                    }
                                });
                            }
                            Err(e) => {
                                tracing::error!("Error accepting connection: {}", e);
                            }
                        }
                    }

                    tracing::info!("SCP server stopped accepting connections");
                }
                Err(e) => {
                    tracing::error!("Failed to bind SCP listener on {}: {}", addr, e);
                }
            }
        });

        Ok(())
    }

    /// Stop the SCP listener
    pub async fn stop(&self) -> Result<()> {
        let mut running = self.running.write().await;
        *running = false;
        tracing::info!("Stopping SCP server");
        Ok(())
    }

    /// Check if server is running
    pub async fn is_running(&self) -> bool {
        *self.running.read().await
    }
}

/// Handle an incoming DICOM association
async fn handle_association(
    _stream: tokio::net::TcpStream,
    ae_title: String,
) -> Result<()> {
    tracing::info!("Handling association for AE: {}", ae_title);

    // NOTE: Full SCP implementation requires:
    // 1. Accept association using ServerAssociationOptions
    // 2. Negotiate presentation contexts (supported SOP classes)
    // 3. Handle incoming DIMSE messages (C-ECHO-RQ, C-STORE-RQ, etc.)
    // 4. Send appropriate responses (C-ECHO-RSP, C-STORE-RSP)
    // 5. Save received DICOM instances to disk
    // 6. Manage association release or abort

    // The dicom-ul crate provides lower-level PDU handling
    // Building a complete SCP requires:
    // - ServerAssociationOptions for accepting connections
    // - DIMSE message parsing and construction
    // - File I/O for storing instances
    // - Status code management

    tracing::warn!("SCP association handling not fully implemented");
    tracing::info!("Would accept association for AE: {}", ae_title);

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_scp_lifecycle() {
        let config = DimseConfig::default();
        let scp = ScpServer::new(config);

        assert!(!scp.is_running().await);
        // Full lifecycle testing requires mock TCP connections
        // scp.start().await.unwrap();
        // assert!(scp.is_running().await);
        // scp.stop().await.unwrap();
        // assert!(!scp.is_running().await);
    }
}
