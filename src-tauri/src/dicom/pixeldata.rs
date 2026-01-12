// Pixel data extraction and rendering

use anyhow::Result;
use dicom_object::InMemDicomObject;
use image::{DynamicImage, ImageBuffer, Luma};

/// Extract and decode pixel data from a DICOM object
/// For now, return raw pixel values as a simplified implementation
pub fn extract_pixel_data(obj: &InMemDicomObject) -> Result<Vec<u16>> {
    use dicom_dictionary_std::tags;

    // Try to get pixel data element
    let pixel_data_elem = obj.element(tags::PIXEL_DATA)?;

    // For now, return placeholder data
    // TODO: Properly decode using dicom-pixeldata crate
    // This requires understanding the transfer syntax and proper decoding

    Err(anyhow::anyhow!("Pixel data decoding not yet fully implemented. Needs proper transfer syntax handling."))
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

/// Convert pixel data to PNG bytes for frontend display
pub fn to_png_bytes(
    pixel_data: &[u16],
    rows: u32,
    cols: u32,
    window_center: f32,
    window_width: f32
) -> Result<Vec<u8>> {
    // Create 8-bit image buffer with windowing applied
    let img_buffer: ImageBuffer<Luma<u8>, Vec<u8>> = ImageBuffer::from_fn(cols, rows, |x, y| {
        let idx = (y * cols + x) as usize;
        let pixel_value = if idx < pixel_data.len() {
            let val = pixel_data[idx] as f32;
            apply_windowing(val, window_center, window_width)
        } else {
            0
        };
        Luma([pixel_value])
    });

    // Convert to PNG bytes
    let mut png_bytes = Vec::new();
    let dynamic_img = DynamicImage::ImageLuma8(img_buffer);
    dynamic_img.write_to(&mut std::io::Cursor::new(&mut png_bytes), image::ImageFormat::Png)?;

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
