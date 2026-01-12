// DICOMweb commands

use crate::dicomweb::{DicomWebEndpoint, qido::QidoQuery};

#[tauri::command]
pub async fn qido_rs(
    endpoint: DicomWebEndpoint,
    query: QidoQuery,
) -> Result<Vec<serde_json::Value>, String> {
    use crate::dicomweb::client::DicomWebClient;

    let client = DicomWebClient::new(endpoint);
    let results = crate::dicomweb::qido::query(&client, query)
        .await
        .map_err(|e| e.to_string())?;

    Ok(results)
}

#[tauri::command]
pub async fn wado_rs(
    endpoint: DicomWebEndpoint,
    study_uid: String,
    series_uid: String,
    instance_uid: String,
) -> Result<String, String> {
    use crate::dicomweb::client::DicomWebClient;
    use base64::{Engine as _, engine::general_purpose};

    let client = DicomWebClient::new(endpoint);
    let data = crate::dicomweb::wado::retrieve_instance(
        &client,
        &study_uid,
        &series_uid,
        &instance_uid,
    )
    .await
    .map_err(|e| e.to_string())?;

    // Return as base64 for frontend
    let base64_data = general_purpose::STANDARD.encode(&data);
    Ok(base64_data)
}

#[tauri::command]
pub async fn stow_rs(
    endpoint: DicomWebEndpoint,
    file_paths: Vec<String>,
) -> Result<StowResult, String> {
    use crate::dicomweb::client::DicomWebClient;
    use std::fs;

    let client = DicomWebClient::new(endpoint);

    // Read all DICOM files
    let mut instances = Vec::new();
    for path in &file_paths {
        let data = fs::read(path).map_err(|e| e.to_string())?;
        instances.push(data);
    }

    // Store instances
    let response = crate::dicomweb::stow::store_instances(&client, None, instances)
        .await
        .map_err(|e| e.to_string())?;

    Ok(StowResult {
        success_count: response.success.len(),
        failed_count: response.failed.len(),
    })
}

#[derive(Debug, serde::Serialize)]
pub struct StowResult {
    pub success_count: usize,
    pub failed_count: usize,
}
