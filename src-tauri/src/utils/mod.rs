// Utility functions

pub mod logging;
pub mod file_helpers;

use std::path::PathBuf;

/// Get application data directory
pub fn get_app_data_dir() -> PathBuf {
    dirs::data_local_dir()
        .unwrap_or_else(|| PathBuf::from("."))
        .join("dicom-toolkit")
}

/// Ensure directory exists
pub fn ensure_dir(path: &PathBuf) -> std::io::Result<()> {
    if !path.exists() {
        std::fs::create_dir_all(path)?;
    }
    Ok(())
}

/// Generate unique filename
pub fn generate_unique_filename(base: &str, extension: &str) -> String {
    use chrono::Utc;
    format!("{}_{}.{}", base, Utc::now().timestamp(), extension)
}
