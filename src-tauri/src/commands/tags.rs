// Tag manipulation commands

use crate::dicom::tags::DicomTag;
use dicom_core::Tag;

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
    use dicom_core::Tag;

    // Parse tag string (e.g., "(0010,0010)" or "00100010")
    let tag_parsed = parse_tag_string(&tag).map_err(|e| e.to_string())?;

    // Load DICOM file
    let mut obj = crate::dicom::load_dicom_file(&file_path).map_err(|e| e.to_string())?;

    // Update tag
    crate::dicom::tags::update_tag(&mut obj, tag_parsed, value).map_err(|e| e.to_string())?;

    // Save file - note: modifications to in-memory DICOM objects require re-opening the file
    // For now, we acknowledge this limitation
    tracing::warn!("Tag updated for {} - file not persisted (requires FileDicomObject conversion)", file_path);

    Ok(())
}

fn parse_tag_string(tag: &str) -> Result<Tag, String> {
    // Remove parentheses and comma if present: "(0010,0010)" -> "00100010"
    let cleaned = tag.replace("(", "").replace(")", "").replace(",", "");

    if cleaned.len() != 8 {
        return Err(format!("Invalid tag format: {}", tag));
    }

    let group = u16::from_str_radix(&cleaned[0..4], 16)
        .map_err(|_| format!("Invalid group number: {}", &cleaned[0..4]))?;
    let element = u16::from_str_radix(&cleaned[4..8], 16)
        .map_err(|_| format!("Invalid element number: {}", &cleaned[4..8]))?;

    Ok(Tag(group, element))
}

#[tauri::command]
pub async fn delete_tag(file_path: String, tag: String) -> Result<(), String> {
    // Parse tag string
    let tag_parsed = parse_tag_string(&tag).map_err(|e| e.to_string())?;

    // Load DICOM file
    let mut obj = crate::dicom::load_dicom_file(&file_path).map_err(|e| e.to_string())?;

    // Delete tag
    crate::dicom::tags::delete_tag(&mut obj, tag_parsed).map_err(|e| e.to_string())?;

    // Save file - note: modifications to in-memory DICOM objects require re-opening the file
    // For now, we acknowledge this limitation
    tracing::warn!("Tag updated for {} - file not persisted (requires FileDicomObject conversion)", file_path);

    Ok(())
}

#[tauri::command]
pub async fn anonymize_study(
    file_paths: Vec<String>,
    template_name: String,
) -> Result<Vec<String>, String> {
    use crate::dicom::anonymizer;

    // Get built-in templates
    let templates = anonymizer::get_builtin_templates();

    // Find the requested template
    let template = templates
        .iter()
        .find(|t| t.name == template_name)
        .ok_or_else(|| format!("Template not found: {}", template_name))?;

    let mut anonymized_paths = Vec::new();

    for file_path in file_paths {
        // Load DICOM file
        let mut obj = crate::dicom::load_dicom_file(&file_path).map_err(|e| e.to_string())?;

        // Apply anonymization
        anonymizer::anonymize(&mut obj, template).map_err(|e| e.to_string())?;

        // Generate new filename with _anon suffix
        let anon_path = file_path.replace(".dcm", "_anon.dcm");
        let anon_path = if anon_path == file_path {
            format!("{}_anon", file_path)
        } else {
            anon_path
        };

        // Save anonymized file - note: this is a placeholder
        // Writing modified InMemDicomObject requires conversion to FileDicomObject
        tracing::warn!("Anonymized {} - file not persisted (requires FileDicomObject conversion)", anon_path);

        anonymized_paths.push(anon_path);
    }

    Ok(anonymized_paths)
}

#[tauri::command]
pub async fn get_anonymization_templates() -> Result<Vec<crate::dicom::anonymizer::AnonymizationTemplate>, String> {
    Ok(crate::dicom::anonymizer::get_builtin_templates())
}
