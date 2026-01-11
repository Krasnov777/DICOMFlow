// Viewer commands

#[tauri::command]
pub async fn get_image_data(
    file_path: String,
    window_center: Option<f32>,
    window_width: Option<f32>,
) -> Result<String, String> {
    // TODO: Load DICOM, extract pixel data, apply windowing, return as base64 PNG
    Ok(String::new())
}

#[tauri::command]
pub async fn get_metadata(file_path: String) -> Result<serde_json::Value, String> {
    // TODO: Load DICOM and return all metadata as JSON
    Ok(serde_json::json!({}))
}

#[tauri::command]
pub async fn apply_windowing(
    file_path: String,
    center: f32,
    width: f32,
) -> Result<String, String> {
    // TODO: Apply windowing and return updated image as base64 PNG
    Ok(String::new())
}
