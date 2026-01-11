# DICOM Basics

## What is DICOM?

DICOM (Digital Imaging and Communications in Medicine) is the international standard for medical images and related information. It defines:

1. **File Format**: How to store medical images
2. **Network Protocol**: How to exchange medical images
3. **Information Model**: How to organize patient/study/series/instance hierarchy

## DICOM File Structure

A DICOM file consists of:

### 1. Preamble (128 bytes)
- Usually filled with zeros
- Can contain application-specific data

### 2. DICOM Prefix (4 bytes)
- Always "DICM" in ASCII
- Identifies file as DICOM

### 3. Data Elements (Tags)
Each tag contains:
- **Tag**: (Group, Element) identifier, e.g., (0010,0010)
- **VR**: Value Representation (data type)
- **Length**: Size of value in bytes
- **Value**: The actual data

### Example Tags
| Tag | Name | VR | Example Value |
|-----|------|----|--------------|
| (0010,0010) | Patient Name | PN | "DOE^JOHN" |
| (0010,0020) | Patient ID | LO | "12345" |
| (0020,000D) | Study Instance UID | UI | "1.2.840.113..." |
| (7FE0,0010) | Pixel Data | OW/OB | [binary image data] |

## Value Representations (VR)

Common VRs:
- **PN** (Person Name): Patient or physician names
- **LO** (Long String): Text up to 64 chars
- **UI** (Unique Identifier): UIDs
- **DA** (Date): YYYYMMDD
- **TM** (Time): HHMMSS
- **DS** (Decimal String): Numeric values
- **US** (Unsigned Short): 16-bit integers
- **OW/OB** (Other Word/Byte): Binary data like pixels

## DICOM Hierarchy

```
Patient
└── Study (e.g., CT Chest exam on 2024-01-15)
    └── Series (e.g., Axial slices)
        └── Instance (individual image)
```

### Unique Identifiers (UIDs)
- **Patient ID**: Identifies patient (not always unique globally)
- **Study Instance UID**: Unique identifier for a study
- **Series Instance UID**: Unique identifier for a series
- **SOP Instance UID**: Unique identifier for an instance

## Transfer Syntaxes

Transfer syntax defines how pixel data is encoded:

### Uncompressed
- **Implicit VR Little Endian**: Most common
- **Explicit VR Little Endian**: VR explicitly stated
- **Explicit VR Big Endian**: Rare

### Compressed
- **JPEG Baseline**: Lossy compression
- **JPEG Lossless**: Lossless compression
- **JPEG 2000**: Advanced compression
- **RLE**: Run-Length Encoding

## IODs (Information Object Definitions)

IODs define which tags are required for specific image types:

- **CT Image IOD**: Required tags for CT scans
- **MR Image IOD**: Required tags for MRI
- **US Image IOD**: Required tags for ultrasound

### Required vs Optional Tags
- **Type 1**: Required, must have value
- **Type 2**: Required, can be empty
- **Type 3**: Optional

## DICOM Networking

### DIMSE (DICOM Message Service Element)

Traditional DICOM networking protocol:

**Service Classes:**
- **C-ECHO**: Verify connectivity
- **C-FIND**: Query for studies
- **C-MOVE**: Retrieve studies (to third party)
- **C-GET**: Retrieve studies (direct)
- **C-STORE**: Send/receive images

**Components:**
- **SCP** (Service Class Provider): Receives requests
- **SCU** (Service Class User): Initiates requests
- **AE Title**: Application Entity identifier
- **Association**: Connection between two DICOM nodes

### DICOMweb

Modern RESTful API for DICOM:

- **QIDO-RS** (Query): Search for studies via HTTP GET
- **WADO-RS** (Retrieve): Fetch images via HTTP GET
- **STOW-RS** (Store): Upload images via HTTP POST

**Advantages:**
- Uses standard HTTP/HTTPS
- No special ports or firewall rules
- Easy authentication (OAuth, API keys)
- Works over the internet

## Pixel Data

### Image Properties
- **Rows/Columns**: Image dimensions
- **Bits Allocated**: Bits per pixel (usually 8 or 16)
- **Photometric Interpretation**:
  - MONOCHROME1: Dark=high value
  - MONOCHROME2: Bright=high value
  - RGB: Color image

### Windowing
Controls brightness/contrast:
- **Window Center (C)**: Middle gray value
- **Window Width (W)**: Range of visible values

Formula:
```
if pixel_value <= (C - W/2): display black
if pixel_value >= (C + W/2): display white
else: scale linearly between black and white
```

### Common Window Presets (CT)
- **Lung**: C=-600, W=1500
- **Bone**: C=400, W=1800
- **Soft Tissue**: C=50, W=350
- **Brain**: C=40, W=80

## Privacy and Anonymization

### Patient Identifiers
Tags that identify patients:
- (0010,0010) Patient Name
- (0010,0020) Patient ID
- (0010,0030) Patient Birth Date
- (0010,0040) Patient Sex
- (0008,0080) Institution Name

### Anonymization Approaches
1. **Remove**: Delete identifying tags
2. **Blank**: Set to empty string
3. **Replace**: Use dummy values
4. **Hash**: One-way hash for consistency
5. **Regenerate UIDs**: New UIDs while preserving relationships

### DICOM Standard Guidelines
DICOM PS3.15 Annex E lists all potentially identifying tags.

## Resources

- [DICOM Standard](https://www.dicomstandard.org/)
- [DICOM Library](https://www.dicomlibrary.com/)
- [Innolitics DICOM Browser](https://dicom.innolitics.com/)
