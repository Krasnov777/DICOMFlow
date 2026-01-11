// DIMSE commands

use crate::dimse::{PacsEndpoint, scu};

#[tauri::command]
pub async fn start_scp(port: u16, ae_title: String) -> Result<(), String> {
    // TODO: Start SCP listener
    Ok(())
}

#[tauri::command]
pub async fn stop_scp() -> Result<(), String> {
    // TODO: Stop SCP listener
    Ok(())
}

#[tauri::command]
pub async fn c_echo(endpoint: PacsEndpoint) -> Result<bool, String> {
    scu::c_echo(&endpoint)
        .await
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn c_find(
    endpoint: PacsEndpoint,
    params: scu::QueryParams,
) -> Result<Vec<scu::StudyResult>, String> {
    scu::c_find(&endpoint, params)
        .await
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn c_move(
    endpoint: PacsEndpoint,
    study_uid: String,
    destination_ae: String,
) -> Result<scu::MoveProgress, String> {
    scu::c_move(&endpoint, &study_uid, &destination_ae)
        .await
        .map_err(|e| e.to_string())
}
