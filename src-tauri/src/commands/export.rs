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
    use dicom_pixeldata::{ConvertOptions, PixelDecoder, VoiLutOption, WindowLevel};
    use std::fs::File;

    // Load DICOM file as FileDicomObject for pixel decoding
    let file_obj = dicom_object::open_file(&file_path).map_err(|e| e.to_string())?;

    // Decode pixel data
    let decoded = file_obj.decode_pixel_data().map_err(|e| e.to_string())?;

    // Build conversion options with windowing
    let mut options = ConvertOptions::new();

    if let (Some(center), Some(width)) = (window_center, window_width) {
        options = options.with_voi_lut(VoiLutOption::Custom(WindowLevel {
            center: center as f64,
            width: width as f64,
        }));
    } else {
        options = options.with_voi_lut(VoiLutOption::Default);
    }

    options = options.force_8bit();

    // Convert to dynamic image
    let dynamic_image = decoded
        .to_dynamic_image_with_options(0, &options)
        .map_err(|e| e.to_string())?;

    // Save to PNG file
    dynamic_image
        .save(&output_path)
        .map_err(|e| format!("Failed to save PNG: {}", e))?;

    tracing::info!("Exported image to {}", output_path);

    Ok(())
}
