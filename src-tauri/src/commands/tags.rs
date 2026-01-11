// Tag manipulation commands

use crate::dicom::tags::DicomTag;

#[tauri::command]
pub async fn get_all_tags(file_path: String) -> Result<Vec<DicomTag>, String> {
    // TODO: Load DICOM and return all tags
    Ok(vec![])
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
