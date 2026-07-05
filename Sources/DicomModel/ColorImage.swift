import Foundation
import CoreGraphics

/// A decoded color DICOM image (US color Doppler, RGB/YBR secondary capture, XA…).
/// These are 2D (single- or multi-frame) and carry no HU/window semantics, so they
/// display in their own path — one RGB CGImage per frame — not the grayscale volume.
public struct ColorImage: Sendable {
    public let width: Int
    public let height: Int
    public let frames: [CGImage]
    public let modality: String

    public var frameCount: Int { frames.count }

    public init(width: Int, height: Int, frames: [CGImage], modality: String) {
        self.width = width; self.height = height; self.frames = frames; self.modality = modality
    }

    /// Build from an interleaved RGB8 buffer covering all frames (row-major).
    public static func fromRGB8(_ rgb: Data, width: Int, height: Int, frames: Int, modality: String) -> ColorImage? {
        guard width > 0, height > 0, frames > 0 else { return nil }
        let perFrame = width * height * 3
        guard rgb.count >= perFrame * frames else { return nil }
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
        var images: [CGImage] = []
        images.reserveCapacity(frames)
        for f in 0 ..< frames {
            let frameData = rgb.subdata(in: f * perFrame ..< (f + 1) * perFrame)
            guard let provider = CGDataProvider(data: frameData as CFData),
                  let cg = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 24,
                                   bytesPerRow: width * 3, space: space, bitmapInfo: info,
                                   provider: provider, decode: nil, shouldInterpolate: true,
                                   intent: .defaultIntent) else { return nil }
            images.append(cg)
        }
        return ColorImage(width: width, height: height, frames: images, modality: modality)
    }
}
