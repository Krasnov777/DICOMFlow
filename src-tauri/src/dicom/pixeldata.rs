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
    use std::time::Instant;

    let total_start = Instant::now();
    tracing::info!("Starting image decode for {:?}", path.as_ref());

    // Load as FileDicomObject (required for PixelDecoder)
    let load_start = Instant::now();
    let file_obj = dicom_object::open_file(path)?;
    tracing::info!("File loaded in {:?}", load_start.elapsed());

    // Decode pixel data using PixelDecoder trait
    let decode_start = Instant::now();
    let decoded = file_obj.decode_pixel_data()?;
    tracing::info!("Pixel data decoded in {:?}", decode_start.elapsed());

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
    let convert_start = Instant::now();
    let dynamic_image = decoded.to_dynamic_image_with_options(0, &options)?;
    tracing::info!("Converted to image in {:?}", convert_start.elapsed());

    // Encode as PNG using image crate
    let png_start = Instant::now();
    use std::io::Cursor;
    let mut png_bytes: Vec<u8> = Vec::new();
    {
        let mut cursor = Cursor::new(&mut png_bytes);
        dynamic_image.write_to(&mut cursor, image::ImageFormat::Png)?;
    }
    tracing::info!("PNG encoded in {:?}, size: {} bytes", png_start.elapsed(), png_bytes.len());

    // Encode as base64
    let b64_start = Instant::now();
    let base64_string = base64::Engine::encode(&base64::engine::general_purpose::STANDARD, &png_bytes);
    tracing::info!("Base64 encoded in {:?}, length: {}", b64_start.elapsed(), base64_string.len());

    tracing::info!("Total image decode time: {:?}", total_start.elapsed());

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
    fn test_window_presets_ct() {
        let presets = get_window_presets("CT");
        assert_eq!(presets.len(), 4);
        assert_eq!(presets[0].name, "Lung");
        assert_eq!(presets[1].name, "Bone");
        assert_eq!(presets[2].name, "Soft Tissue");
        assert_eq!(presets[3].name, "Brain");
    }

    #[test]
    fn test_window_presets_default() {
        let presets = get_window_presets("MR");
        assert_eq!(presets.len(), 1);
        assert_eq!(presets[0].name, "Default");
        assert_eq!(presets[0].center, 128.0);
        assert_eq!(presets[0].width, 256.0);
    }

    #[test]
    fn test_window_preset_values() {
        let presets = get_window_presets("CT");
        let lung = &presets[0];
        assert_eq!(lung.center, -600.0);
        assert_eq!(lung.width, 1500.0);

        let bone = &presets[1];
        assert_eq!(bone.center, 400.0);
        assert_eq!(bone.width, 1800.0);
    }
}
