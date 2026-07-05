import SwiftUI

/// Menu-bar commands: Open / Open Recent, viewer navigation, and Help.
/// Navigation items are disabled outside the viewer so their bare-key
/// equivalents (→ ← Space) fall through to focused controls / text fields
/// instead of being globally hijacked.
struct DicomFlowCommands: Commands {
    @ObservedObject var state: AppState

    private var viewing: Bool { state.mode == .viewer && state.viewerState.hasImage }

    var body: some Commands {
        // File → Open… / Open Recent
        CommandGroup(replacing: .newItem) {
            Button("Open…") { state.openWithPanel() }
                .keyboardShortcut("o", modifiers: .command)
            Menu("Open Recent") {
                ForEach(state.recents) { r in
                    Button(r.name) { state.openRecent(r) }
                }
                if !state.recents.isEmpty {
                    Divider()
                    Button("Clear Menu") { state.clearRecents() }
                }
            }
            .disabled(state.recents.isEmpty)
        }

        // Image navigation (only active while viewing).
        CommandMenu("Image") {
            Button("Next Slice") { state.viewerState.stepSlice(+1) }
                .keyboardShortcut(.rightArrow, modifiers: []).disabled(!viewing)
            Button("Previous Slice") { state.viewerState.stepSlice(-1) }
                .keyboardShortcut(.leftArrow, modifiers: []).disabled(!viewing)
            Button(state.viewerState.isPlaying ? "Pause Cine" : "Play Cine") {
                state.viewerState.isPlaying.toggle()
            }
            .keyboardShortcut(.space, modifiers: []).disabled(!viewing)
            Divider()
            Button("Invert Grayscale") { state.viewerState.invert.toggle() }.disabled(!viewing)
            Button("Show Info Overlays") { state.viewerState.showOverlays.toggle() }.disabled(!viewing)
            Button("Reset View") { state.viewerState.resetView() }.disabled(!viewing)
        }

        // Help → cheat-sheet + re-openable Welcome.
        CommandGroup(replacing: .help) {
            Button("Keyboard & Gestures") { state.showShortcuts = true }
                .keyboardShortcut("/", modifiers: .command)
            Button("Welcome to DicomFlow") { state.showWelcome = true }
        }
    }
}
