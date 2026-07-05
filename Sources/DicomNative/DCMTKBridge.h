#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Objective-C facade over DCMTK (C++). Swift calls these; the .mm file is the
/// only place that includes DCMTK headers, keeping C++ out of the Swift side.
@interface DCMTKBridge : NSObject

/// Read every element of a DICOM file as an array of dictionaries with keys:
/// "tag", "keyword", "name", "vr", "value". Returns nil + error on failure.
+ (nullable NSArray<NSDictionary<NSString *, NSString *> *> *)readTags:(NSString *)path
                                                                error:(NSError **)error;

/// Transfer syntax name of a file (e.g. "Explicit VR Little Endian"), or nil.
+ (nullable NSString *)transferSyntaxName:(NSString *)path;

/// Render a DICOM Structured Report (SR) to readable plain text (the content
/// tree). Returns nil + error if the file is not a valid SR.
+ (nullable NSString *)readReportText:(NSString *)path error:(NSError **)error;

/// Validate a DICOM file for basic conformance (part-10 meta, required UIDs, UID
/// format, SOP class, image attributes, per-element VR checks). Returns
/// @{ ok:BOOL, errors:[NSString], warnings:[NSString], info:{sopClass, sopClassUID,
/// transferSyntax, modality} }.
+ (NSDictionary *)validateFile:(NSString *)path;

/// Register all decompression codecs (JPEG, JPEG-LS, RLE). Safe to call repeatedly.
+ (void)registerCodecs;

/// Render a file's first frame to a display bitmap (windowed 8-bit gray or
/// interleaved RGB8) for preview / OCR. Returns @{ data, rows, columns, samples }
/// or nil if it can't be rendered.
+ (nullable NSDictionary *)renderDisplay8:(NSString *)path;

/// Black out pixel regions (burned-in-text redaction) across all frames and save
/// to `outputPath` (uncompressed). `rects` are [x,y,w,h] normalized (top-left
/// origin). Also sets BurnedInAnnotation = NO. Returns @{ success, message }.
+ (NSDictionary *)redactFile:(NSString *)path
                       rects:(NSArray<NSArray<NSNumber *> *> *)rects
                  outputPath:(NSString *)outputPath;

/// A dcmdump-style structural dump of a file: file-meta + dataset as a nested
/// element tree (tag, VR, length, value; sequences indented). Long values
/// (e.g. Pixel Data) are shortened. Returns nil if the file can't be read.
+ (nullable NSString *)dumpFile:(NSString *)path;

/// Parse a DICOMDIR file into its Patient → Study → Series hierarchy. Each series
/// carries the absolute paths of its referenced instances (resolved against the
/// DICOMDIR's folder). Returns @{ success, message, baseDir, patients:[ @{name,
/// patientID, studies:[ @{uid, date, description, series:[ @{uid, modality,
/// number, description, files:[abs paths] } ] } ] } ] }.
+ (NSDictionary *)readDicomDir:(NSString *)path;

/// Generate a synthetic DICOM series (a stackable volume) into `dir`.
/// `sopClass` is a Storage SOP Class UID (CT/MR → 16-bit; else 8-bit SC).
/// `pattern`: "sphere" | "gradient" | "checkerboard" | "rings" | "noise" | "solid".
/// Returns @{ success, count, dir, files:[paths], message }.
+ (NSDictionary *)generateDatasetToDir:(NSString *)dir
                              sopClass:(NSString *)sopClass
                                  rows:(int)rows columns:(int)columns
                                slices:(int)slices pattern:(NSString *)pattern;

/// Decode one instance to 16-bit pixels + geometry. Returns a dictionary:
///   pixelData: NSData (little-endian int16, rows*cols)
///   rows, columns, bitsAllocated, pixelRepresentation, frames: NSNumber
///   slope, intercept, windowCenter, windowWidth, sliceThickness: NSNumber
///   position: NSArray<NSNumber> (ImagePositionPatient, 3)
///   orientation: NSArray<NSNumber> (ImageOrientationPatient, 6)
///   pixelSpacing: NSArray<NSNumber> (row, col)
///   modality, seriesUID, sopUID: NSString
/// Returns nil + error on failure (e.g. unsupported bit depth).
+ (nullable NSDictionary *)decodeFile:(NSString *)path error:(NSError **)error;

/// Fast metadata-only scan of a folder, grouped by series. Returns an array of
/// @{ seriesUID, description, modality, seriesNumber, patient, studyDescription,
///    files:NSArray<NSString> } (pixel data is not read).
+ (NSArray<NSDictionary *> *)scanSeries:(NSString *)directory;

/// Apply edits and save to a NEW file. `edits` is an array of
/// @{ "keyword": NSString, "value": NSString or NSNull(=delete) }.
/// Pixel-geometry tags are refused. Returns @{ outputPath, applied[], skipped[] }.
+ (nullable NSDictionary *)editTags:(NSString *)path
                              edits:(NSArray<NSDictionary *> *)edits
                         outputPath:(NSString *)outputPath
                              error:(NSError **)error;

/// Anonymize a batch of files into `outputDir` with a shared UID map (so a
/// series stays internally consistent). `profile` keys:
///   replacePatientName / replacePatientID: NSString or NSNull
///   clearDates / clearIdentifiers / removePrivateTags / regenerateUIDs: NSNumber(bool)
/// Returns @{ processed, uidsRemapped, warnings[] }.
+ (nullable NSDictionary *)anonymize:(NSArray<NSString *> *)paths
                           outputDir:(NSString *)outputDir
                             profile:(NSDictionary *)profile
                               error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
