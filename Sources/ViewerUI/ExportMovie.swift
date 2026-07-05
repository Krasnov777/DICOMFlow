import AVFoundation
import AppKit
import CoreVideo

/// Writes H.264 .mov files from offscreen renders: a 2D slice sweep through the
/// volume, or a 3D MIP turntable.
enum ExportMovie {

    /// Render every slice along `axis` and write a movie. Returns frames written.
    @discardableResult
    static func sliceSweep(volume: Volume, axis: MPRAxis, winCenter: Float, winWidth: Float,
                           invert: Bool, fps: Int = 12, size: Int = 1024, to url: URL) throws -> Int {
        let m = volume.meta
        let n = axis.sliceCount(nx: m.nx, ny: m.ny, nz: m.nz)
        return try write(url: url, fps: fps, frameCount: n) { i in
            MPRPlaneRenderer.renderOffscreen(
                volume: volume, axis: axis,
                sliceFrac: Float(i) / Float(max(n - 1, 1)),
                winCenter: winCenter, winWidth: winWidth, size: size,
                zoom: 1, pan: .zero, invert: invert)
        }
    }

    /// 360° MIP turntable of the volume (uses the current window/level).
    @discardableResult
    static func turntable(volume: Volume, winCenter: Float, winWidth: Float,
                          frames: Int = 90, fps: Int = 24, size: Int = 768, to url: URL) throws -> Int {
        let renderer = RaycastRenderer()
        renderer.volume = volume
        renderer.mode = .mip
        renderer.winCenter = winCenter
        renderer.winWidth = winWidth
        renderer.camera.set(.anterior)
        let step = 2 * Float.pi / Float(frames)
        return try write(url: url, fps: fps, frameCount: frames) { _ in
            renderer.camera.orbit(dx: step, dy: 0)
            return renderer.renderOffscreen(size: size)
        }
    }

    // MARK: writer core

    private static func write(url: URL, fps: Int, frameCount: Int,
                              frame: (Int) -> CGImage?) throws -> Int {
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        var input: AVAssetWriterInput?
        var adaptor: AVAssetWriterInputPixelBufferAdaptor?
        var written = 0

        for i in 0..<frameCount {
            guard let img = frame(i) else { continue }
            // Configure lazily from the first frame's (even) dimensions.
            if input == nil {
                let w = img.width & ~1, h = img.height & ~1
                let inp = AVAssetWriterInput(mediaType: .video, outputSettings: [
                    AVVideoCodecKey: AVVideoCodecType.h264,
                    AVVideoWidthKey: w, AVVideoHeightKey: h,
                ])
                let ad = AVAssetWriterInputPixelBufferAdaptor(
                    assetWriterInput: inp,
                    sourcePixelBufferAttributes: [
                        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                        kCVPixelBufferWidthKey as String: w,
                        kCVPixelBufferHeightKey as String: h,
                    ])
                writer.add(inp)
                writer.startWriting()
                writer.startSession(atSourceTime: .zero)
                input = inp; adaptor = ad
            }
            guard let input, let adaptor,
                  let buf = pixelBuffer(from: img, pool: adaptor.pixelBufferPool) else { continue }
            while !input.isReadyForMoreMediaData { usleep(2000) }
            adaptor.append(buf, withPresentationTime: CMTime(value: CMTimeValue(written), timescale: CMTimeScale(fps)))
            written += 1
        }
        guard let input else { throw NSError(domain: "ExportMovie", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "no frames rendered"]) }
        input.markAsFinished()
        let sema = DispatchSemaphore(value: 0)
        writer.finishWriting { sema.signal() }
        sema.wait()
        if writer.status == .failed {
            throw writer.error ?? NSError(domain: "ExportMovie", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "writer failed"])
        }
        return written
    }

    private static func pixelBuffer(from image: CGImage, pool: CVPixelBufferPool?) -> CVPixelBuffer? {
        var buf: CVPixelBuffer?
        if let pool {
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buf)
        }
        if buf == nil {
            CVPixelBufferCreate(nil, image.width & ~1, image.height & ~1,
                                kCVPixelFormatType_32BGRA, nil, &buf)
        }
        guard let buf else { return nil }
        CVPixelBufferLockBaseAddress(buf, [])
        defer { CVPixelBufferUnlockBaseAddress(buf, []) }
        guard let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buf),
                                  width: CVPixelBufferGetWidth(buf),
                                  height: CVPixelBufferGetHeight(buf),
                                  bitsPerComponent: 8,
                                  bytesPerRow: CVPixelBufferGetBytesPerRow(buf),
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                      | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0,
                                   width: CVPixelBufferGetWidth(buf),
                                   height: CVPixelBufferGetHeight(buf)))
        return buf
    }

    /// Save-panel wrapper used by the viewer UI.
    @MainActor
    static func savePanel(suggested: String, _ export: @escaping (URL) throws -> Int,
                          done: @escaping (Result<Int, Error>) -> Void) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggested
        panel.allowedContentTypes = [.quickTimeMovie]
        guard panel.runModal() == .OK, let url = panel.url else {
            done(.success(0))   // cancelled — let the caller clear its busy state
            return
        }
        Task.detached(priority: .userInitiated) {
            do {
                let n = try export(url)
                await MainActor.run { done(.success(n)) }
            } catch {
                await MainActor.run { done(.failure(error)) }
            }
        }
    }
}
