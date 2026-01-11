// File system helper functions

use std::path::{Path, PathBuf};

/// Check if a file is a DICOM file by attempting to read it
pub fn is_dicom_file<P: AsRef<Path>>(path: P) -> bool {
    dicom_object::open_file(path).is_ok()
}

/// Scan directory recursively for DICOM files
pub fn find_dicom_files<P: AsRef<Path>>(dir: P, recursive: bool) -> Vec<PathBuf> {
    let mut dicom_files = Vec::new();

    if let Ok(entries) = std::fs::read_dir(dir) {
        for entry in entries.flatten() {
            let path = entry.path();

            if path.is_file() && is_dicom_file(&path) {
                dicom_files.push(path);
            } else if recursive && path.is_dir() {
                dicom_files.extend(find_dicom_files(&path, true));
            }
        }
    }

    dicom_files
}

/// Get file size in bytes
pub fn get_file_size<P: AsRef<Path>>(path: P) -> std::io::Result<u64> {
    let metadata = std::fs::metadata(path)?;
    Ok(metadata.len())
}
