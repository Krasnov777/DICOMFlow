// Viewer commands

use crate::dicom;

#[tauri::command]
pub async fn get_image_data(
    file_path: String,
    window_center: Option<f32>,
    window_width: Option<f32>,
) -> Result<String, String> {
    // Load DICOM file and decode pixel data with optional windowing
    let base64_png = dicom::pixeldata::load_and_decode_to_png_base64(
        &file_path,
        window_center,
        window_width,
    )
    .map_err(|e| e.to_string())?;

    Ok(base64_png)
}

#[tauri::command]
pub async fn get_metadata(file_path: String) -> Result<serde_json::Value, String> {
    // Load DICOM file
    let obj = dicom::load_dicom_file(&file_path).map_err(|e| e.to_string())?;

    // Extract metadata
    let metadata = dicom::extract_metadata(&obj).map_err(|e| e.to_string())?;

    // Get windowing defaults if available
    let windowing = dicom::pixeldata::get_default_windowing(&obj);

    // Build JSON response
    let mut json = serde_json::to_value(metadata).map_err(|e| e.to_string())?;

    if let Some((center, width)) = windowing {
        json["window_center"] = serde_json::json!(center);
        json["window_width"] = serde_json::json!(width);
    }

    Ok(json)
}

#[tauri::command]
pub async fn apply_windowing(
    file_path: String,
    center: f32,
    width: f32,
) -> Result<String, String> {
    // Re-decode with new windowing parameters
    let base64_png = dicom::pixeldata::load_and_decode_to_png_base64(
        &file_path,
        Some(center),
        Some(width),
    )
    .map_err(|e| e.to_string())?;

    Ok(base64_png)
}
