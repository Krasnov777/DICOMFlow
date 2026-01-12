// Pixel data extraction and rendering

use anyhow::Result;
use dicom_object::{FileDicomObject, InMemDicomObject};
use dicom_pixeldata::{ConvertOptions, PixelDecoder, VoiLutOption, WindowLevel};
use std::path::Path;

/// Load DICOM file and decode pixel data to base64 PNG with optional windowing
/// This function loads the file as FileDicomObject to access PixelDecoder trait
pub fn load_and_decode_to_png_base64<P: AsRef<Path>>(
    path: P,
    window_center: Option<f32>,
    window_width: Option<f32>,
) -> Result<String> {
    // Load as FileDicomObject (required for PixelDecoder)
    let file_obj = dicom_object::open_file(path)?;

    // Decode pixel data using PixelDecoder trait
    let decoded = file_obj.decode_pixel_data()?;

    // Build conversion options with optional windowing
    let mut options = ConvertOptions::new();

    if let (Some(center), Some(width)) = (window_center, window_width) {
        // Apply custom windowing
        options = options.with_voi_lut(VoiLutOption::Custom(WindowLevel {
            center: center as f64,
            width: width as f64,
        }));
    } else {
        // Use default windowing from DICOM file
        options = options.with_voi_lut(VoiLutOption::Default);
    }

    // Force 8-bit output for PNG
    options = options.force_8bit();

    // Convert to dynamic image (frame 0)
    let dynamic_image = decoded.to_dynamic_image_with_options(0, &options)?;

    // Encode as PNG using image crate
    use std::io::Cursor;
    let mut png_bytes: Vec<u8> = Vec::new();
    {
        let mut cursor = Cursor::new(&mut png_bytes);
        dynamic_image.write_to(&mut cursor, image::ImageFormat::Png)?;
    }

    // Encode as base64
    let base64_string = base64::Engine::encode(&base64::engine::general_purpose::STANDARD, &png_bytes);

    Ok(base64_string)
}

/// Get default window center and width from DICOM file
pub fn get_default_windowing(obj: &InMemDicomObject) -> Option<(f32, f32)> {
    use dicom_dictionary_std::tags;

    let center = obj
        .element(tags::WINDOW_CENTER)
        .ok()?
        .to_str()
        .ok()?
        .parse::<f32>()
        .ok()?;

    let width = obj
        .element(tags::WINDOW_WIDTH)
        .ok()?
        .to_str()
        .ok()?
        .parse::<f32>()
        .ok()?;

    Some((center, width))
}

/// Get image dimensions from DICOM object
pub fn get_image_dimensions(obj: &InMemDicomObject) -> Result<(u32, u32)> {
    use dicom_dictionary_std::tags;

    let rows = obj.element(tags::ROWS)?
        .to_int::<u32>()?;
    let cols = obj.element(tags::COLUMNS)?
        .to_int::<u32>()?;

    Ok((cols, rows))
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
    fn test_image_dimensions() {
        // TODO: Test with sample DICOM file
    }
}
