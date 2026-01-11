// DIMSE configuration utilities

use super::{DimseConfig, PacsEndpoint};
use anyhow::Result;

/// Load SCP configuration from settings
pub fn load_scp_config() -> Result<DimseConfig> {
    // TODO: Load from database or config file
    Ok(DimseConfig::default())
}

/// Save SCP configuration to settings
pub fn save_scp_config(config: &DimseConfig) -> Result<()> {
    // TODO: Save to database or config file
    Ok(())
}

/// Load all saved PACS endpoints
pub fn load_pacs_endpoints() -> Result<Vec<PacsEndpoint>> {
    // TODO: Load from database
    Ok(vec![])
}

/// Save a PACS endpoint
pub fn save_pacs_endpoint(endpoint: &PacsEndpoint) -> Result<()> {
    // TODO: Save to database
    Ok(())
}

/// Delete a PACS endpoint
pub fn delete_pacs_endpoint(name: &str) -> Result<()> {
    // TODO: Delete from database
    Ok(())
}
