import Foundation

/// Geometry + windowing metadata for a decoded volume (the native DCMTK path
/// builds this directly; the int16 pixel buffer is passed alongside as Data).
public struct VolumeMeta: Decodable, Sendable {
    public let dtype: String
    public let dims: [Int]            // [nx, ny, nz]
    public let spacing: [Float]       // [sx, sy, sz] mm
    public let origin: [Float]
    public let orientation: [Float]   // 6 direction cosines
    public let slope: Float
    public let intercept: Float
    public let defaultWindowCenter: Float
    public let defaultWindowWidth: Float
    public let valueMin: Int
    public let valueMax: Int
    public let modality: String
    public let seriesCount: Int
    public let warnings: [String]

    public var nx: Int { dims[0] }
    public var ny: Int { dims[1] }
    public var nz: Int { dims[2] }

    /// Memberwise init for the native (DCMTK) path, which builds meta directly.
    public init(dtype: String = "int16", dims: [Int],
                spacing: [Float], origin: [Float], orientation: [Float],
                slope: Float, intercept: Float,
                defaultWindowCenter: Float, defaultWindowWidth: Float,
                valueMin: Int, valueMax: Int, modality: String,
                seriesCount: Int, warnings: [String]) {
        self.dtype = dtype; self.dims = dims
        self.spacing = spacing; self.origin = origin; self.orientation = orientation
        self.slope = slope; self.intercept = intercept
        self.defaultWindowCenter = defaultWindowCenter
        self.defaultWindowWidth = defaultWindowWidth
        self.valueMin = valueMin; self.valueMax = valueMax
        self.modality = modality; self.seriesCount = seriesCount; self.warnings = warnings
    }
}
