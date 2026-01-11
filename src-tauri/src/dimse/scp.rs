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
        let mut running = self.running.write().await;
        if *running {
            return Ok(());
        }

        *running = true;
        tracing::info!("Starting SCP server on port {}", self.config.port);

        // TODO: Implement DICOM SCP using dicom-ul
        // - Listen for incoming associations
        // - Handle C-STORE requests
        // - Handle C-ECHO requests
        // - Save received DICOM files

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

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_scp_lifecycle() {
        let config = DimseConfig::default();
        let scp = ScpServer::new(config);

        assert!(!scp.is_running().await);
        // scp.start().await.unwrap();
        // assert!(scp.is_running().await);
        // scp.stop().await.unwrap();
        // assert!(!scp.is_running().await);
    }
}
