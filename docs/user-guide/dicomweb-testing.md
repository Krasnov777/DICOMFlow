# DICOMweb Testing Guide

## Overview

The DICOMweb Testing panel provides a Postman-like interface for testing DICOMweb APIs (QIDO-RS, WADO-RS, STOW-RS).

## QIDO-RS (Query)

QIDO-RS allows you to search for studies, series, or instances.

### Example: Search for Studies

1. **Method**: Select "QIDO-RS"
2. **Endpoint**: `https://your-server.com/dicomweb/studies`
3. **Query Parameters**:
   ```
   PatientName=John*
   StudyDate=20240101-20241231
   limit=10
   ```
4. **Headers**:
   ```json
   {
     "Accept": "application/dicom+json"
   }
   ```
5. Click "Send Request"

### Search Levels
- **Studies**: `/dicomweb/studies`
- **Series**: `/dicomweb/series`
- **Instances**: `/dicomweb/instances`

## WADO-RS (Retrieve)

WADO-RS allows you to retrieve DICOM objects or metadata.

### Example: Retrieve Study Metadata

1. **Method**: Select "WADO-RS"
2. **Endpoint**: `https://your-server.com/dicomweb/studies/{studyUID}/metadata`
3. **Headers**:
   ```json
   {
     "Accept": "application/dicom+json"
   }
   ```

### Retrieve Formats
- DICOM objects: `Accept: application/dicom`
- Metadata: `Accept: application/dicom+json`
- Rendered images: `Accept: image/png` or `image/jpeg`

## STOW-RS (Store)

STOW-RS allows you to upload DICOM instances to a server.

### Example: Upload DICOM Files

1. **Method**: Select "STOW-RS"
2. **Endpoint**: `https://your-server.com/dicomweb/studies`
3. **Body**: Select DICOM files to upload
4. **Headers**:
   ```json
   {
     "Content-Type": "multipart/related; type=\"application/dicom\"",
     "Accept": "application/dicom+json"
   }
   ```

## Authentication

### Basic Auth
```json
{
  "Authorization": "Basic base64(username:password)"
}
```

### Bearer Token
```json
{
  "Authorization": "Bearer your-token-here"
}
```

### Custom Headers
Add any custom headers required by your server.

## Request History

- All requests are saved in the request history panel
- Click on a previous request to replay it
- Export request history as JSON for sharing

## Export as cURL

Click "Export as cURL" to get a command-line version of your request:

```bash
curl -X GET "https://server.com/dicomweb/studies?PatientName=John*" \
  -H "Accept: application/dicom+json" \
  -H "Authorization: Bearer token"
```

## Tips

1. Use wildcards (`*`) in search parameters for partial matches
2. Check the DICOM standard for valid search tags
3. Some servers require specific Accept headers
4. Use the request history to iterate on queries
5. Test connectivity with a simple QIDO query first
