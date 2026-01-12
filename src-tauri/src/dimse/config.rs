// DIMSE configuration utilities

use super::{DimseConfig, PacsEndpoint};
use crate::database::DbPool;
use anyhow::Result;

/// Load SCP configuration from settings
pub async fn load_scp_config(pool: &DbPool) -> Result<DimseConfig> {
    // Try to load from database
    let result = sqlx::query_scalar::<_, String>(
        "SELECT value FROM settings WHERE key = 'scp_config'"
    )
    .fetch_optional(pool)
    .await?;

    if let Some(json_str) = result {
        let config: DimseConfig = serde_json::from_str(&json_str)?;
        Ok(config)
    } else {
        // Return default if not found
        Ok(DimseConfig::default())
    }
}

/// Save SCP configuration to settings
pub async fn save_scp_config(pool: &DbPool, config: &DimseConfig) -> Result<()> {
    let json_str = serde_json::to_string(config)?;

    sqlx::query(
        "INSERT OR REPLACE INTO settings (key, value, updated_at)
         VALUES ('scp_config', ?, CURRENT_TIMESTAMP)"
    )
    .bind(&json_str)
    .execute(pool)
    .await?;

    Ok(())
}

/// Load all saved PACS endpoints
pub async fn load_pacs_endpoints(pool: &DbPool) -> Result<Vec<PacsEndpoint>> {
    let rows = sqlx::query_scalar::<_, String>(
        "SELECT config_json FROM connections WHERE connection_type = 'dimse' ORDER BY name"
    )
    .fetch_all(pool)
    .await?;

    let mut endpoints = Vec::new();
    for json_str in rows {
        let endpoint: PacsEndpoint = serde_json::from_str(&json_str)?;
        endpoints.push(endpoint);
    }

    Ok(endpoints)
}

/// Save a PACS endpoint
pub async fn save_pacs_endpoint(pool: &DbPool, endpoint: &PacsEndpoint) -> Result<()> {
    let json_str = serde_json::to_string(endpoint)?;

    // Insert or update based on name
    sqlx::query(
        "INSERT INTO connections (name, connection_type, config_json, created_at, updated_at)
         VALUES (?, 'dimse', ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
         ON CONFLICT(id) DO UPDATE SET
             config_json = excluded.config_json,
             updated_at = CURRENT_TIMESTAMP
         WHERE name = ? AND connection_type = 'dimse'"
    )
    .bind(&endpoint.name)
    .bind(&json_str)
    .bind(&endpoint.name)
    .execute(pool)
    .await?;

    Ok(())
}

/// Delete a PACS endpoint
pub async fn delete_pacs_endpoint(pool: &DbPool, name: &str) -> Result<()> {
    sqlx::query(
        "DELETE FROM connections WHERE name = ? AND connection_type = 'dimse'"
    )
    .bind(name)
    .execute(pool)
    .await?;

    Ok(())
}
