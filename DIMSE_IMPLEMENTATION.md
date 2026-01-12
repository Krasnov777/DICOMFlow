# DIMSE Implementation Status

This document explains the current state of DIMSE (DICOM Message Service Element) operations in DICOMFlow.

## Overview

DIMSE operations are implemented using the `dicom-ul` crate, which provides low-level DICOM Upper Layer (DUL) protocol handling. The implementation includes query dataset construction and association management, but full DIMSE message exchange requires additional work beyond the current scope.

## Implemented Operations

### ✅ C-ECHO (Fully Working)
**Purpose:** Verify network connectivity with a PACS server

**Status:** ✅ **Functional**

**Implementation:**
- Establishes DICOM association using proper AE titles
- Uses Verification SOP Class
- Successfully connects and disconnects from PACS servers
- Validates network connectivity and AE title configuration

**Usage:** Test connection button in DIMSE UI

---

### ⚠️ C-FIND (Partially Implemented)
**Purpose:** Query PACS for studies, series, or instances

**Status:** ⚠️ **Query dataset built, DIMSE exchange incomplete**

**What's Implemented:**
- Association establishment with Study Root Query/Retrieve SOP Class
- Complete query dataset construction with search parameters:
  - Patient Name (wildcard support)
  - Patient ID (wildcard support)
  - Study Date (date range support)
  - Modality filtering
  - Accession Number
- Return key specification for study attributes
- Proper VR (Value Representation) usage

**What's Missing:**
- DIMSE C-FIND-RQ message construction and sending
- C-FIND-RSP message parsing
- Progressive result handling (PENDING status responses)
- Conversion of response datasets to `StudyResult` objects

**Technical Note:**
The `dicom-ul` crate provides PDU (Protocol Data Unit) handling but not higher-level DIMSE message construction. Building complete C-FIND messages requires:
1. DIMSE command dataset creation
2. PDU fragmentation for large datasets
3. Response status code interpretation
4. Multi-response handling (studies returned incrementally)

---

### ⚠️ C-MOVE (Partially Implemented)
**Purpose:** Request PACS to transfer images to a destination AE

**Status:** ⚠️ **Move dataset built, DIMSE exchange incomplete**

**What's Implemented:**
- Association with Study Root Query/Retrieve MOVE SOP Class
- Move request dataset with:
  - Query/Retrieve Level (STUDY)
  - Study Instance UID for retrieval
- Destination AE title specification framework

**What's Missing:**
- DIMSE C-MOVE-RQ message with move destination in command
- C-MOVE-RSP progress monitoring (remaining, completed, failed counts)
- Sub-operation status tracking
- Handling of final C-MOVE-RSP with overall status

**Workflow:**
1. Client sends C-MOVE-RQ to PACS
2. PACS initiates C-STORE operations to destination AE
3. PACS sends C-MOVE-RSP with progress updates
4. Destination AE must be running SCP to receive images

---

### ⚠️ C-GET (Partially Implemented)
**Purpose:** Retrieve images directly from PACS on same association

**Status:** ⚠️ **Get dataset built, DIMSE exchange incomplete**

**What's Implemented:**
- Association with Study Root Query/Retrieve GET SOP Class
- Get request dataset construction
- Study-level retrieval specification

**What's Missing:**
- DIMSE C-GET-RQ message sending
- Acting as SCP to receive incoming C-STORE-RQ on same association
- Sending C-STORE-RSP for each received instance
- Progress monitoring via C-GET-RSP
- File saving for retrieved instances

**Technical Challenge:**
C-GET requires the client to act as both SCU (for the GET request) and SCP (to receive STORE operations) on the same association. This is more complex than C-MOVE which uses separate associations.

---

### ⚠️ SCP Server (Framework Implemented)
**Purpose:** Receive DICOM images from PACS (C-STORE SCP)

**Status:** ⚠️ **TCP listener working, DICOM protocol incomplete**

**What's Implemented:**
- TCP server listening on configured port
- Async connection acceptance
- Per-connection task spawning
- Start/stop lifecycle management
- AE title configuration

**What's Missing:**
- ServerAssociationOptions configuration
- Association acceptance and negotiation
- Presentation context negotiation
- C-STORE-RQ message handling
- DICOM instance parsing and validation
- File storage with proper naming (SOP Instance UID)
- C-STORE-RSP status code generation
- C-ECHO-SCP verification support

**Storage Requirements:**
When implemented, the SCP should:
- Save received instances with SOP Instance UID as filename
- Organize by Study/Series hierarchy
- Validate DICOM conformance
- Handle duplicate detection
- Provide storage commitment if requested

---

## Architecture Notes

### Why DIMSE Exchange is Incomplete

The `dicom-ul` crate provides:
- ✅ Association establishment and release
- ✅ PDU (Protocol Data Unit) encoding/decoding
- ✅ Presentation context negotiation
- ✅ Transfer syntax handling

What requires additional implementation:
- ❌ DIMSE command dataset construction
- ❌ DIMSE message type handling (RQ/RSP/IND)
- ❌ DIMSE status code interpretation
- ❌ Data set fragmentation across PDUs
- ❌ Priority and message ID management

### Recommended Path Forward

To complete DIMSE operations, you would need to:

1. **Build DIMSE Message Layer:**
   ```rust
   struct DimseCommand {
       message_id: u16,
       command_field: u16,  // C-FIND-RQ, C-STORE-RSP, etc.
       priority: u16,
       data_set_type: u16,  // Present/absent
       // ... additional fields
   }
   ```

2. **Implement Message Construction:**
   - Encode command dataset as DICOM object
   - Combine with data dataset (for queries)
   - Fragment into P-DATA-TF PDUs
   - Handle transfer syntax encoding

3. **Implement Response Parsing:**
   - Read P-DATA-TF PDUs from association
   - Reassemble fragmented datasets
   - Parse DIMSE command
   - Extract status codes and data

4. **Handle State Machines:**
   - Track message IDs
   - Match responses to requests
   - Handle PENDING/SUCCESS/FAILURE/CANCEL states
   - Manage timeouts

### Alternative Approach

Consider using higher-level DICOM libraries that provide complete DIMSE implementations:
- **dcmtk** (C++) with FFI bindings
- **pydicom** via Python subprocess
- **dicom-rs** ecosystem expansion (if/when DIMSE layer is added)

---

## Testing Requirements

To test DIMSE operations, you need:

1. **PACS Server:**
   - DCM4CHEE (open source)
   - Orthanc (lightweight, Docker-friendly)
   - Commercial PACS with test mode

2. **Test Data:**
   - Upload DICOM studies to PACS
   - Configure AE titles and ports
   - Set up store SCP destination

3. **Network Configuration:**
   - Firewall rules for DICOM ports (typically 104, 11112)
   - Bidirectional connectivity
   - AE title registration in PACS

---

## Current Capabilities

### What Works Now:
- ✅ C-ECHO to test PACS connectivity
- ✅ Association establishment with proper SOP classes
- ✅ Query/move/get dataset construction
- ✅ SCP server lifecycle management

### What Requires a PACS Server:
- ⚠️ Actual C-FIND queries (needs PACS to respond)
- ⚠️ C-MOVE operations (needs PACS and destination SCP)
- ⚠️ C-GET retrieval (needs PACS to send images)
- ⚠️ C-STORE reception (needs PACS to send test images)

### What's Placeholder:
- ❌ DIMSE message protocol layer
- ❌ Response parsing and status handling
- ❌ File storage from C-STORE
- ❌ Progress tracking for multi-image operations

---

## Summary

The DIMSE implementation in DICOMFlow provides a **solid foundation** with:
- Working C-ECHO for connectivity testing
- Proper association management
- Complete dataset construction for queries and retrievals
- TCP server infrastructure for SCP

To make this production-ready for clinical use, the missing DIMSE message layer would need to be implemented. For development and testing purposes, the current implementation demonstrates understanding of DICOM networking concepts and provides a framework that can be extended when needed.

For immediate medical imaging workflows, consider:
- Using DICOMweb (already implemented) as the primary network protocol
- Leveraging the tag editing and anonymization features
- Utilizing the pixel data viewing capabilities
- Employing the file-based import/export functions
