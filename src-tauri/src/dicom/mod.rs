pub mod parser;
pub mod pixeldata;
pub mod tags;
pub mod anonymizer;

use anyhow::Result;
use dicom_object::{InMemDicomObject, DicomObject};
use dicom_core::header::Header;
use std::path::Path;

/// Load a DICOM file from disk
pub fn load_dicom_file<P: AsRef<Path>>(path: P) -> Result<InMemDicomObject> {
    let file_obj = dicom_object::open_file(path)?;
    // Convert FileDicomObject to InMemDicomObject
    Ok(file_obj.into_inner())
}

/// Save a DICOM object to disk
pub fn save_dicom_file<P: AsRef<Path>>(obj: &InMemDicomObject, path: P) -> Result<()> {
    use dicom_object::FileDicomObject;
    use dicom_object::mem::InMemElement;

    // Get meta information or create default
    let meta = obj.meta()
        .cloned()
        .unwrap_or_else(|| {
            // Create a minimal valid file meta information
            use dicom_object::meta::FileMetaTableBuilder;
            use dicom_core::dicom_value;
            use dicom_dictionary_std::uids;

            FileMetaTableBuilder::new()
                // Explicit VR Little Endian
                .transfer_syntax(uids::EXPLICIT_VR_LITTLE_ENDIAN)
                .media_storage_sop_class_uid(uids::SECONDARY_CAPTURE_IMAGE_STORAGE)
                .media_storage_sop_instance_uid(
                    obj.element_by_name("SOPInstanceUID")
                        .ok()
                        .and_then(|e| e.to_str().ok())
                        .map(|s| s.to_string())
                        .unwrap_or_else(|| "1.2.3.4.5.6.7.8.9".to_string())
                )
                .build()
                .expect("Failed to create file meta table")
        });

    // Create a FileDicomObject with meta information
    let mut new_obj = FileDicomObject::new_empty_with_meta(meta);

    // Copy all elements from InMemDicomObject to FileDicomObject
    for elem in obj.iter() {
        let new_elem = InMemElement::new(
            elem.tag(),
            elem.vr(),
            elem.value().clone(),
        );
        new_obj.put_element(new_elem);
    }

    // Write to file
    new_obj.write_to_file(path)?;

    Ok(())
}

/// Extract basic metadata from a DICOM object
pub fn extract_metadata(obj: &InMemDicomObject) -> Result<DicomMetadata> {
    use dicom_dictionary_std::tags;

    let study_uid = obj
        .element(tags::STUDY_INSTANCE_UID)?
        .to_str()?
        .to_string();

    let series_uid = obj
        .element(tags::SERIES_INSTANCE_UID)?
        .to_str()?
        .to_string();

    let sop_uid = obj
        .element(tags::SOP_INSTANCE_UID)?
        .to_str()?
        .to_string();

    let patient_name = obj
        .element(tags::PATIENT_NAME)
        .ok()
        .and_then(|e| e.to_str().ok())
        .map(|s| s.to_string());

    let patient_id = obj
        .element(tags::PATIENT_ID)
        .ok()
        .and_then(|e| e.to_str().ok())
        .map(|s| s.to_string());

    let study_date = obj
        .element(tags::STUDY_DATE)
        .ok()
        .and_then(|e| e.to_str().ok())
        .map(|s| s.to_string());

    let modality = obj
        .element(tags::MODALITY)
        .ok()
        .and_then(|e| e.to_str().ok())
        .map(|s| s.to_string());

    Ok(DicomMetadata {
        study_instance_uid: study_uid,
        series_instance_uid: series_uid,
        sop_instance_uid: sop_uid,
        patient_name,
        patient_id,
        study_date,
        modality,
    })
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct DicomMetadata {
    pub study_instance_uid: String,
    pub series_instance_uid: String,
    pub sop_instance_uid: String,
    pub patient_name: Option<String>,
    pub patient_id: Option<String>,
    pub study_date: Option<String>,
    pub modality: Option<String>,
}
