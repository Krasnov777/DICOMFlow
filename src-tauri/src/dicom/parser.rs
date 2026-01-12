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
pub struct ParsedDicomFile {
    pub path: String,
    pub object: InMemDicomObject,
}

/// Parse multiple DICOM files from a directory
pub fn parse_directory<P: AsRef<Path>>(dir: P) -> Result<Vec<ParsedDicomFile>> {
    let mut files = Vec::new();

    for entry in std::fs::read_dir(dir)? {
        let entry = entry?;
        let path = entry.path();

        if path.is_file() {
            match dicom_object::open_file(&path) {
                Ok(file_obj) => {
                    files.push(ParsedDicomFile {
                        path: path.to_string_lossy().to_string(),
                        object: file_obj.into_inner(),
                    });
                }
                Err(e) => {
                    tracing::warn!("Failed to parse {:?}: {}", path, e);
                    continue;
                }
            }
        }
    }

    Ok(files)
}

#[cfg(test)]
mod tests {
    use super::*;

    // Add tests with sample DICOM files
}
