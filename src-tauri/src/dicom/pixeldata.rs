// Pixel data extraction and rendering

use anyhow::Result;
use dicom_object::InMemDicomObject;
use dicom_pixeldata::{DecodedPixelData, PixelDecoder};
use image::{DynamicImage, ImageBuffer, Luma};

/// Extract and decode pixel data from a DICOM object
pub fn extract_pixel_data(_obj: &InMemDicomObject) -> Result<DecodedPixelData> {
    // TODO: Implement pixel data extraction using dicom-pixeldata crate
    // The API requires using PixelDecoder trait
    Err(anyhow::anyhow!("Pixel data extraction not yet implemented"))
}

/// Convert decoded pixel data to PNG bytes for frontend display
pub fn to_png_bytes(pixel_data: &DecodedPixelData, window_center: f32, window_width: f32) -> Result<Vec<u8>> {
    // TODO: Implement windowing logic
    // - Apply window center/width
    // - Handle different pixel formats (grayscale, RGB)
    // - Apply modality LUT
    // - Convert to 8-bit for PNG

    // Placeholder implementation
    let mut png_bytes = Vec::new();

    // Convert to PNG using image crate
    // ...

    Ok(png_bytes)
}

/// Apply windowing to pixel values
pub fn apply_windowing(pixel_value: f32, center: f32, width: f32) -> u8 {
    let min = center - width / 2.0;
    let max = center + width / 2.0;

    if pixel_value <= min {
        0
    } else if pixel_value >= max {
        255
    } else {
        (((pixel_value - min) / (max - min)) * 255.0) as u8
    }
}

/// Get common windowing presets based on modality
pub fn get_window_presets(modality: &str) -> Vec<WindowPreset> {
    match modality {
        "CT" => vec![
            WindowPreset { name: "Lung".to_string(), center: -600.0, width: 1500.0 },
            WindowPreset { name: "Bone".to_string(), center: 400.0, width: 1800.0 },
            WindowPreset { name: "Soft Tissue".to_string(), center: 50.0, width: 350.0 },
            WindowPreset { name: "Brain".to_string(), center: 40.0, width: 80.0 },
        ],
        _ => vec![
            WindowPreset { name: "Default".to_string(), center: 128.0, width: 256.0 },
        ],
    }
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct WindowPreset {
    pub name: String,
    pub center: f32,
    pub width: f32,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_windowing() {
        assert_eq!(apply_windowing(0.0, 128.0, 256.0), 0);
        assert_eq!(apply_windowing(128.0, 128.0, 256.0), 127);
        assert_eq!(apply_windowing(255.0, 128.0, 256.0), 255);
    }
}
