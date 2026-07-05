import SwiftUI

/// Vertical sidebar of series thumbnails for multi-series studies.
struct SeriesSidebar: View {
    @EnvironmentObject var viewer: ViewerState
    @EnvironmentObject var sidecar: DicomEngine
    @State private var thumbs: [String: CGImage] = [:]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: Theme.Spacing.sm) {
                ForEach(viewer.series) { s in card(s) }
            }
            .padding(Theme.Spacing.sm)
        }
        .background(.background.secondary)
    }

    private func card(_ s: DicomEngine.SeriesInfo) -> some View {
        let selected = viewer.selectedSeriesID == s.id
        return VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.chip).fill(.black)
                if let img = thumbs[s.id] {
                    Image(decorative: img, scale: 1).resizable().scaledToFit()
                } else {
                    // SR has no pixels → show a report glyph instead of the
                    // generic slice-stack placeholder.
                    Image(systemName: s.modality == "SR" ? "doc.text.below.ecg" : "square.stack.3d.up")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 92)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.chip))
            Text(label(s)).font(.caption2).lineLimit(1)
            Text("\(s.modality) · \(s.count)").font(.caption2).foregroundStyle(.secondary)
        }
        .padding(6)
        .background(selected ? Theme.accent.opacity(0.18) : (hovering == s.id ? Color.primary.opacity(0.06) : .clear),
                    in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .strokeBorder(selected ? Theme.accent : .clear, lineWidth: 1.5))
        .contentShape(Rectangle())
        .onHover { hovering = $0 ? s.id : (hovering == s.id ? nil : hovering) }
        .onTapGesture { viewer.selectSeries(s, client: sidecar) }
        // One selectable, labeled element for VoiceOver/keyboard instead of loose text.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label(s)), \(s.modality), \(s.count) image\(s.count == 1 ? "" : "s")")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { viewer.selectSeries(s, client: sidecar) }
        .task(id: s.id) {
            if thumbs[s.id] == nil { thumbs[s.id] = await sidecar.thumbnail(files: s.files) }
        }
    }

    @State private var hovering: String?

    private func label(_ s: DicomEngine.SeriesInfo) -> String {
        if !s.description.isEmpty { return s.description }
        if !s.seriesNumber.isEmpty { return "Series \(s.seriesNumber)" }
        return s.modality
    }
}
