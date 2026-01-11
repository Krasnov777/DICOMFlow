// Export commands

#[tauri::command]
pub async fn export_tags_json(file_path: String, output_path: String) -> Result<(), String> {
    // TODO: Export tags as JSON
    Ok(())
}

#[tauri::command]
pub async fn export_tags_xml(file_path: String, output_path: String) -> Result<(), String> {
    // TODO: Export tags as XML
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
