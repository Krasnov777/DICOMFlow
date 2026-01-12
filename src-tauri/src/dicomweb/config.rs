// DICOMweb configuration utilities

use super::DicomWebEndpoint;
use crate::database::DbPool;
use anyhow::Result;

/// Load all saved DICOMweb endpoints
pub async fn load_dicomweb_endpoints(pool: &DbPool) -> Result<Vec<DicomWebEndpoint>> {
    let rows = sqlx::query_scalar::<_, String>(
        "SELECT config_json FROM connections WHERE connection_type = 'dicomweb' ORDER BY name"
    )
    .fetch_all(pool)
    .await?;

    let mut endpoints = Vec::new();
    for json_str in rows {
        let endpoint: DicomWebEndpoint = serde_json::from_str(&json_str)?;
        endpoints.push(endpoint);
    }

    Ok(endpoints)
}

/// Save a DICOMweb endpoint
pub async fn save_dicomweb_endpoint(pool: &DbPool, endpoint: &DicomWebEndpoint) -> Result<()> {
    let json_str = serde_json::to_string(endpoint)?;

    // Insert or update based on name
    sqlx::query(
        "INSERT INTO connections (name, connection_type, config_json, created_at, updated_at)
         VALUES (?, 'dicomweb', ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
         ON CONFLICT(id) DO UPDATE SET
             config_json = excluded.config_json,
             updated_at = CURRENT_TIMESTAMP
         WHERE name = ? AND connection_type = 'dicomweb'"
    )
    .bind(&endpoint.name)
    .bind(&json_str)
    .bind(&endpoint.name)
    .execute(pool)
    .await?;

    Ok(())
}

/// Delete a DICOMweb endpoint
pub async fn delete_dicomweb_endpoint(pool: &DbPool, name: &str) -> Result<()> {
    sqlx::query(
        "DELETE FROM connections WHERE name = ? AND connection_type = 'dicomweb'"
    )
    .bind(name)
    .execute(pool)
    .await?;

    Ok(())
}
