import SwiftUI

/// Displays a color DICOM image (US color Doppler, RGB/YBR secondary capture, …)
/// — its own 2D path, since color images carry no HU/window/MPR semantics. The
/// current frame is driven by `viewer.colorFrame` (multi-frame clips cine via the
/// bottom bar / Space).
struct ColorImageView: View {
    @EnvironmentObject var viewer: ViewerState
    let image: ColorImage

    var body: some View {
        let idx = min(max(viewer.colorFrame, 0), image.frameCount - 1)
        Image(decorative: image.frames[idx], scale: 1, orientation: .up)
            .resizable()
            .interpolation(.medium)
            .aspectRatio(CGFloat(image.width) / CGFloat(max(image.height, 1)), contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(8)
    }
}
