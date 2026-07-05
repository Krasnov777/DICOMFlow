import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Save a rendered CGImage to PNG via the standard save panel.
enum ExportImage {
    static func savePNG(_ image: CGImage, suggested: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = suggested
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }
}
