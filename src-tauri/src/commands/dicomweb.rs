// DICOMweb commands

use crate::dicomweb::{DicomWebEndpoint, qido::QidoQuery};

#[tauri::command]
pub async fn qido_rs(
    endpoint: DicomWebEndpoint,
    query: QidoQuery,
) -> Result<Vec<serde_json::Value>, String> {
    // TODO: Execute QIDO-RS query
    Ok(vec![])
}

#[tauri::command]
pub async fn wado_rs(
    endpoint: DicomWebEndpoint,
    study_uid: String,
    series_uid: String,
    instance_uid: String,
) -> Result<String, String> {
    // TODO: Execute WADO-RS retrieve and return base64 data
    Ok(String::new())
}

#[tauri::command]
pub async fn stow_rs(
    endpoint: DicomWebEndpoint,
    file_paths: Vec<String>,
) -> Result<StowResult, String> {
    // TODO: Execute STOW-RS store
    Ok(StowResult {
        success_count: 0,
        failed_count: 0,
    })
}

#[derive(Debug, serde::Serialize)]
pub struct StowResult {
    pub success_count: usize,
    pub failed_count: usize,
}
