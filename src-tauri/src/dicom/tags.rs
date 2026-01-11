// DICOM tag extraction and manipulation

use anyhow::Result;
use dicom_core::{DataElement, Tag, VR};
use dicom_core::header::Header;
use dicom_object::InMemDicomObject;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// Extract all tags from a DICOM object as a structured format
pub fn extract_all_tags(obj: &InMemDicomObject) -> Vec<DicomTag> {
    obj.iter()
        .map(|elem| DicomTag::from_element(elem))
        .collect()
}

/// Convert tags to JSON
pub fn tags_to_json(obj: &InMemDicomObject) -> Result<String> {
    let tags = extract_all_tags(obj);
    Ok(serde_json::to_string_pretty(&tags)?)
}

/// Convert tags to XML
pub fn tags_to_xml(obj: &InMemDicomObject) -> Result<String> {
    // TODO: Implement DICOM XML format
    Ok(String::from("<?xml version=\"1.0\"?>\n<dicom></dicom>"))
}

/// Update a tag value in a DICOM object
pub fn update_tag(obj: &mut InMemDicomObject, tag: Tag, value: String) -> Result<()> {
    // TODO: Implement tag update with proper VR handling
    Ok(())
}

/// Delete a tag from a DICOM object
pub fn delete_tag(obj: &mut InMemDicomObject, tag: Tag) -> Result<()> {
    obj.remove_element(tag);
    Ok(())
}

/// Search tags by keyword
pub fn search_tags(obj: &InMemDicomObject, query: &str) -> Vec<DicomTag> {
    let all_tags = extract_all_tags(obj);
    let query_lower = query.to_lowercase();

    all_tags
        .into_iter()
        .filter(|tag| {
            tag.name.to_lowercase().contains(&query_lower)
                || tag.value.to_lowercase().contains(&query_lower)
                || format!("{:?}", tag.tag).to_lowercase().contains(&query_lower)
        })
        .collect()
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DicomTag {
    pub tag: String,        // e.g., "(0010,0010)"
    pub name: String,       // e.g., "Patient Name"
    pub vr: String,         // e.g., "PN"
    pub vm: String,         // e.g., "1"
    pub value: String,      // String representation of value
    pub is_private: bool,
}

impl DicomTag {
    pub fn from_element(elem: &DataElement<InMemDicomObject>) -> Self {
        let tag = elem.tag();
        let vr = elem.vr();
        let value = elem.to_str().map(|v| v.to_string()).unwrap_or_else(|_| String::new());

        DicomTag {
            tag: format!("({:04X},{:04X})", tag.group(), tag.element()),
            name: tag.to_string(), // TODO: Get proper tag name from dictionary
            vr: format!("{:?}", vr),
            vm: "1".to_string(), // TODO: Calculate actual VM
            value,
            is_private: tag.group() % 2 == 1, // Private tags have odd group numbers
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // Add tests
}
