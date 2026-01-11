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
    // TODO: Scan directory for DICOM files and return list
    Ok(vec![])
}

#[derive(Debug, serde::Serialize)]
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
