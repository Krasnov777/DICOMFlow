// Tag manipulation commands

use crate::dicom::tags::DicomTag;

#[tauri::command]
pub async fn get_all_tags(file_path: String) -> Result<Vec<DicomTag>, String> {
    let obj = crate::dicom::load_dicom_file(&file_path).map_err(|e| e.to_string())?;
    let tags = crate::dicom::tags::extract_all_tags(&obj);
    Ok(tags)
}

#[tauri::command]
pub async fn update_tag(
    file_path: String,
    tag: String,
    value: String,
) -> Result<(), String> {
    // TODO: Update tag in DICOM file
    Ok(())
}

#[tauri::command]
pub async fn delete_tag(file_path: String, tag: String) -> Result<(), String> {
    // TODO: Delete tag from DICOM file
    Ok(())
}

#[tauri::command]
pub async fn anonymize_study(
    file_paths: Vec<String>,
    template_name: String,
) -> Result<Vec<String>, String> {
    // TODO: Anonymize DICOM files using template
    Ok(vec![])
}
