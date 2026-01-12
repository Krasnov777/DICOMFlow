// File operations commands

use crate::dicom;
use tauri::State;

#[tauri::command]
pub async fn open_dicom_file(path: String) -> Result<DicomFileInfo, String> {
    let obj = dicom::load_dicom_file(&path).map_err(|e| e.to_string())?;
    let metadata = dicom::extract_metadata(&obj).map_err(|e| e.to_string())?;

    Ok(DicomFileInfo {
        path,
        study_instance_uid: metadata.study_instance_uid,
        series_instance_uid: metadata.series_instance_uid,
        sop_instance_uid: metadata.sop_instance_uid,
        patient_name: metadata.patient_name,
        patient_id: metadata.patient_id,
        study_date: metadata.study_date,
        modality: metadata.modality,
    })
}

#[tauri::command]
pub async fn open_dicom_directory(path: String) -> Result<Vec<DicomFileInfo>, String> {
    let parsed_files = dicom::parser::parse_directory(&path).map_err(|e| e.to_string())?;

    let mut file_infos = Vec::new();

    for parsed_file in parsed_files {
        match dicom::extract_metadata(&parsed_file.object) {
            Ok(metadata) => {
                file_infos.push(DicomFileInfo {
                    path: parsed_file.path,
                    study_instance_uid: metadata.study_instance_uid,
                    series_instance_uid: metadata.series_instance_uid,
                    sop_instance_uid: metadata.sop_instance_uid,
                    patient_name: metadata.patient_name,
                    patient_id: metadata.patient_id,
                    study_date: metadata.study_date,
                    modality: metadata.modality,
                });
            }
            Err(e) => {
                tracing::warn!("Failed to extract metadata: {}", e);
                continue;
            }
        }
    }

    Ok(file_infos)
}

#[derive(Debug, Clone, serde::Serialize)]
pub struct DicomFileInfo {
    pub path: String,
    pub study_instance_uid: String,
    pub series_instance_uid: String,
    pub sop_instance_uid: String,
    pub patient_name: Option<String>,
    pub patient_id: Option<String>,
    pub study_date: Option<String>,
    pub modality: Option<String>,
}

#[derive(Debug, serde::Serialize)]
pub struct SeriesInfo {
    pub series_instance_uid: String,
    pub description: Option<String>,
    pub modality: Option<String>,
    pub instances: Vec<DicomFileInfo>,
}

#[derive(Debug, serde::Serialize)]
pub struct StudyInfo {
    pub study_instance_uid: String,
    pub patient_name: Option<String>,
    pub patient_id: Option<String>,
    pub study_date: Option<String>,
    pub series: Vec<SeriesInfo>,
}

#[tauri::command]
pub async fn organize_directory(path: String) -> Result<StudyInfo, String> {
    use std::collections::HashMap;

    let file_infos = open_dicom_directory(path).await?;

    if file_infos.is_empty() {
        return Err("No DICOM files found in directory".to_string());
    }

    // Group files by series
    let mut series_map: HashMap<String, Vec<DicomFileInfo>> = HashMap::new();

    for file_info in file_infos {
        series_map
            .entry(file_info.series_instance_uid.clone())
            .or_insert_with(Vec::new)
            .push(file_info);
    }

    // Create series info
    let mut series_list: Vec<SeriesInfo> = series_map
        .into_iter()
        .map(|(series_uid, instances)| {
            let modality = instances.first().and_then(|i| i.modality.clone());
            SeriesInfo {
                series_instance_uid: series_uid,
                description: None, // Would need to read SeriesDescription tag
                modality,
                instances,
            }
        })
        .collect();

    // Sort series by UID
    series_list.sort_by(|a, b| a.series_instance_uid.cmp(&b.series_instance_uid));

    // Get study info from first file
    let first_file = series_list
        .first()
        .and_then(|s| s.instances.first())
        .ok_or("No files found")?;

    Ok(StudyInfo {
        study_instance_uid: first_file.study_instance_uid.clone(),
        patient_name: first_file.patient_name.clone(),
        patient_id: first_file.patient_id.clone(),
        study_date: first_file.study_date.clone(),
        series: series_list,
    })
}
