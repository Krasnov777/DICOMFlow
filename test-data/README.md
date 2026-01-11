# Test Data

This directory contains DICOM test files for development and testing.

## Directory Structure

- `samples/`: Real DICOM samples from public datasets
- `synthetic/`: Synthetically generated DICOM files for specific test cases

## Sample DICOM Files

### Public Datasets

You can download public DICOM samples from:

1. **The Cancer Imaging Archive (TCIA)**
   - URL: https://www.cancerimagingarchive.net/
   - License: Varies by collection
   - Good source for real clinical data

2. **dcm4che Test Data**
   - URL: https://github.com/dcm4che/dcm4che/tree/master/dcm4che-test-data
   - License: Apache 2.0
   - Small test files for various modalities

3. **DICOM Library**
   - URL: https://www.dicomlibrary.com/
   - Various sample DICOM files
   - Good for testing different transfer syntaxes

### Recommended Test Files

Place the following in `samples/`:

1. **CT-MONO2-16-brain.dcm** - Basic CT scan
2. **MR-MONO2-16-head.dcm** - Basic MRI
3. **US-RGB-8-esopecho.dcm** - RGB ultrasound
4. **CR-MONO1-10-chest.dcm** - Chest X-ray (MONO1)

## Synthetic Test Files

The `synthetic/` directory should contain:

1. **minimal.dcm** - Minimal valid DICOM file
2. **large-multiframe.dcm** - Multi-frame image for performance testing
3. **compressed-jpeg.dcm** - JPEG compressed transfer syntax
4. **private-tags.dcm** - File with private tags for anonymization testing
5. **malformed.dcm** - Intentionally malformed for error handling tests

## Generating Synthetic Files

You can use tools like:

- **dcmtk**: `dcmconv`, `dcmodify` for creating test files
- **pydicom**: Python library for DICOM manipulation
- **Custom scripts**: See `scripts/generate_test_data.py` (future)

## Usage in Tests

### Rust Tests
```rust
#[test]
fn test_parse_ct() {
    let path = "test-data/samples/CT-MONO2-16-brain.dcm";
    let obj = dicom::load_dicom_file(path).unwrap();
    assert_eq!(obj.element(tags::MODALITY).unwrap().to_str().unwrap(), "CT");
}
```

### Frontend Tests
```javascript
// Mock file path for testing
const testFile = '/test-data/samples/CT-MONO2-16-brain.dcm';
```

## License and Attribution

- Ensure all sample files are properly licensed for testing
- Attribute sources in test documentation
- Do not commit patient-identifiable data
- Anonymize any real clinical data before committing

## Adding New Test Files

1. Place file in appropriate directory (`samples/` or `synthetic/`)
2. Document the file in this README
3. Add tests that use the file
4. Ensure file is anonymized if from real source

## .gitignore

Large DICOM files should not be committed to the repository. Instead:

1. Document where to download them
2. Add download scripts
3. Keep only small (<100KB) test files in git
