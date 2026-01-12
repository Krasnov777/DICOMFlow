// Export commands

#[tauri::command]
pub async fn export_tags_json(file_path: String, output_path: String) -> Result<(), String> {
    use std::fs;

    // Load DICOM file
    let obj = crate::dicom::load_dicom_file(&file_path).map_err(|e| e.to_string())?;

    // Export to JSON
    let json = crate::dicom::tags::tags_to_json(&obj).map_err(|e| e.to_string())?;

    // Write to file
    fs::write(&output_path, json).map_err(|e| e.to_string())?;

    Ok(())
}

#[tauri::command]
pub async fn export_tags_xml(file_path: String, output_path: String) -> Result<(), String> {
    use std::fs;

    // Load DICOM file
    let obj = crate::dicom::load_dicom_file(&file_path).map_err(|e| e.to_string())?;

    // Export to XML
    let xml = crate::dicom::tags::tags_to_xml(&obj).map_err(|e| e.to_string())?;

    // Write to file
    fs::write(&output_path, xml).map_err(|e| e.to_string())?;

    Ok(())
}

#[tauri::command]
pub async fn export_image_png(
    file_path: String,
    output_path: String,
    window_center: Option<f32>,
    window_width: Option<f32>,
) -> Result<(), String> {
    // TODO: Export image as PNG with windowing
    Ok(())
}
