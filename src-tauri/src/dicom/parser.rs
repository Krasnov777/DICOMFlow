// DICOM file parsing utilities

use anyhow::Result;
use dicom_object::InMemDicomObject;
use std::path::Path;

/// Parse a DICOM file and validate its structure
pub fn parse_and_validate<P: AsRef<Path>>(path: P) -> Result<InMemDicomObject> {
    let file_obj = dicom_object::open_file(path)?;

    // TODO: Add validation logic
    // - Check required tags
    // - Validate VR values
    // - Check IOD conformance

    Ok(file_obj.into_inner())
}

/// DICOM file with its path
#[derive(Debug)]
pub struct ParsedDicomFile {
    pub path: String,
    pub object: InMemDicomObject,
}

/// Parse multiple DICOM files from a directory (recursive)
pub fn parse_directory<P: AsRef<Path>>(dir: P) -> Result<Vec<ParsedDicomFile>> {
    use walkdir::WalkDir;
    use std::sync::{Arc, Mutex};
    use rayon::prelude::*;

    let files = Arc::new(Mutex::new(Vec::new()));

    // Collect all file paths first
    let paths: Vec<_> = WalkDir::new(dir)
        .follow_links(false)
        .max_depth(10)
        .into_iter()
        .filter_map(|e| e.ok())
        .filter(|e| e.file_type().is_file())
        .map(|e| e.path().to_path_buf())
        .collect();

    tracing::info!("Found {} files to process", paths.len());

    // Process files in parallel
    paths.par_iter().for_each(|path| {
        // Try to open and parse the file
        match dicom_object::open_file(path) {
            Ok(file_obj) => {
                let mut files_lock = files.lock().unwrap();
                files_lock.push(ParsedDicomFile {
                    path: path.to_string_lossy().to_string(),
                    object: file_obj.into_inner(),
                });
            }
            Err(_) => {
                // Not a DICOM file or corrupt, skip silently
            }
        }
    });

    let result = Arc::try_unwrap(files)
        .unwrap()
        .into_inner()
        .unwrap();

    tracing::info!("Successfully parsed {} DICOM files", result.len());

    Ok(result)
}

/// Quickly scan directory for DICOM files and extract minimal metadata
/// This is faster than parse_directory as it only reads required tags
pub fn scan_directory_fast<P: AsRef<Path>>(dir: P) -> Result<Vec<MinimalFileInfo>> {
    use walkdir::WalkDir;
    use rayon::prelude::*;
    use dicom_dictionary_std::tags;

    let paths: Vec<_> = WalkDir::new(dir)
        .follow_links(false)
        .max_depth(10)
        .into_iter()
        .filter_map(|e| e.ok())
        .filter(|e| e.file_type().is_file())
        .map(|e| e.path().to_path_buf())
        .collect();

    // Process in parallel, reading only minimum required tags
    let results: Vec<MinimalFileInfo> = paths
        .par_iter()
        .filter_map(|path| {
            match dicom_object::open_file(path) {
                Ok(obj) => {
                    // Extract only the tags we need
                    let study_uid = obj.element(tags::STUDY_INSTANCE_UID)
                        .ok()?
                        .to_str()
                        .ok()?
                        .to_string();

                    let series_uid = obj.element(tags::SERIES_INSTANCE_UID)
                        .ok()?
                        .to_str()
                        .ok()?
                        .to_string();

                    let sop_uid = obj.element(tags::SOP_INSTANCE_UID)
                        .ok()?
                        .to_str()
                        .ok()?
                        .to_string();

                    let patient_name = obj.element(tags::PATIENT_NAME)
                        .ok()
                        .and_then(|e| e.to_str().ok())
                        .map(|s| s.to_string());

                    let patient_id = obj.element(tags::PATIENT_ID)
                        .ok()
                        .and_then(|e| e.to_str().ok())
                        .map(|s| s.to_string());

                    let study_date = obj.element(tags::STUDY_DATE)
                        .ok()
                        .and_then(|e| e.to_str().ok())
                        .map(|s| s.to_string());

                    let modality = obj.element(tags::MODALITY)
                        .ok()
                        .and_then(|e| e.to_str().ok())
                        .map(|s| s.to_string());

                    Some(MinimalFileInfo {
                        path: path.to_string_lossy().to_string(),
                        study_instance_uid: study_uid,
                        series_instance_uid: series_uid,
                        sop_instance_uid: sop_uid,
                        patient_name,
                        patient_id,
                        study_date,
                        modality,
                    })
                }
                Err(_) => None,
            }
        })
        .collect();

    Ok(results)
}

#[derive(Debug, Clone)]
pub struct MinimalFileInfo {
    pub path: String,
    pub study_instance_uid: String,
    pub series_instance_uid: String,
    pub sop_instance_uid: String,
    pub patient_name: Option<String>,
    pub patient_id: Option<String>,
    pub study_date: Option<String>,
    pub modality: Option<String>,
}

#[cfg(test)]
mod tests {
    use super::*;

    // Add tests with sample DICOM files
}
