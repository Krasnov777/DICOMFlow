pub mod scp;
pub mod scu;
pub mod config;

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DimseConfig {
    pub ae_title: String,
    pub port: u16,
    pub max_pdu_size: u32,
    pub storage_path: String,
}

impl Default for DimseConfig {
    fn default() -> Self {
        Self {
            ae_title: "DICOM_TOOLKIT".to_string(),
            port: 11112,
            max_pdu_size: 16384,
            storage_path: "./dicom_storage".to_string(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PacsEndpoint {
    pub name: String,
    pub ae_title: String,
    pub host: String,
    pub port: u16,
    pub our_ae_title: String,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_default_config() {
        let config = DimseConfig::default();
        assert_eq!(config.ae_title, "DICOM_TOOLKIT");
        assert_eq!(config.port, 11112);
    }
}
