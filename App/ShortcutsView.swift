import SwiftUI

/// Keyboard & gesture reference (Help → Keyboard & Gestures, ⌘/).
struct ShortcutsView: View {
    var dismiss: () -> Void

    private let keyboard: [(String, String)] = [
        ("← →  or  ↑ ↓", "Previous / next slice"),
        ("Space", "Play / pause cine"),
        ("1 – 6", "Select tool (W/L · Pan · Probe · Measure · ROI · Angle)"),
        ("A / C / S", "Axial / Coronal / Sagittal (2D layout)"),
        ("I", "Invert grayscale"),
        ("O", "Toggle corner info overlays"),
        ("R", "Reset zoom/pan (2D·MPR) · reset camera (3D)"),
        ("⌘O", "Open a file or folder"),
        ("⌘/", "This shortcuts reference"),
    ]
    private let gestures: [(String, String)] = [
        ("Scroll / two-finger swipe", "Scrub through slices"),
        ("Right-drag", "Window / Level (any tool)"),
        ("Pinch / magnify", "Zoom"),
        ("Drag (Pan tool, or ⌥-drag in 3D)", "Pan"),
        ("Two-finger drag (3D)", "Orbit the volume"),
        ("Click / drag in an MPR pane", "Move the linked crosshair"),
        ("Drag a file/folder onto the window", "Open it"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack {
                Label("Keyboard & Gestures", systemImage: "keyboard").font(.title2.weight(.semibold))
                Spacer()
                Button("Done", action: dismiss).keyboardShortcut(.defaultAction)
            }
            HStack(alignment: .top, spacing: Theme.Spacing.xl) {
                section("Keyboard", rows: keyboard)
                section("Trackpad & Mouse", rows: gestures)
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(width: 640)
    }

    private func section(_ title: String, rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title).font(.headline).foregroundStyle(.secondary)
            ForEach(rows, id: \.0) { key, desc in
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.md) {
                    Text(key).font(.callout.monospaced().weight(.medium))
                        .frame(width: 200, alignment: .leading)
                    Text(desc).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
