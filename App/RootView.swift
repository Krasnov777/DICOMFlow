import SwiftUI

struct RootView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var engine: DicomEngine
    @AppStorage("didWelcome") private var didWelcome = false

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // No navigationTitle: it sat in the leading toolbar flow and lurched
            // left/right while the NavigationSplitView repositioned the sidebar
            // toggle during the open/close animation. The centred mode picker is
            // enough identity.
            .navigationTitle("")
            .toolbarBackground(.visible, for: .windowToolbar)
            .onAppear { if !didWelcome { state.showWelcome = true } }
            .onOpenURL { state.open($0) }
            .sheet(isPresented: $state.showWelcome, onDismiss: { didWelcome = true }) {
                WelcomeView { state.showWelcome = false }
            }
            .sheet(isPresented: $state.showShortcuts) {
                ShortcutsView { state.showShortcuts = false }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    // Custom binding: entering the Viewer while the Tester sidebar
                    // is open first slides the sidebar closed, THEN switches — so
                    // the toolbar doesn't snap left when the sidebar-less Viewer
                    // takes over. No animation on the mode set itself (the content
                    // handles its own cross-fade); animating the binding would make
                    // the window toolbar animate its reflow.
                    Picker("Mode", selection: Binding(
                        get: { state.mode },
                        set: { selectMode($0) })) {
                        ForEach(AppMode.allCases) { mode in
                            Label(mode.rawValue, systemImage: mode.symbol).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
                // Settings gear, top-right in both modes (⌘, also works).
                ToolbarItem(placement: .primaryAction) {
                    SettingsLink {
                        Image(systemName: "gearshape")
                    }
                    .help("Settings (⌘,)")
                    .accessibilityLabel("Settings")
                }
            }
    }

    private var content: some View {
        // Cross-fade the content area, but scope the animation to THIS subtree
        // (not the mode binding) so the window toolbar still snaps instantly and
        // doesn't animate its reflow between the two container types.
        ZStack {
            switch state.mode {
            case .tester:
                TesterRootView(columnVisibility: $state.testerColumns)
                    .environmentObject(state).environmentObject(engine)
                    .transition(.opacity)
            case .viewer:
                ViewerRootView().environmentObject(state).environmentObject(engine)
                    .transition(.opacity)
            }
        }
        .animation(.smooth, value: state.mode)
    }

    /// Switch modes; when entering the Viewer with the Tester sidebar open, slide
    /// it closed first so the toolbar doesn't jump.
    private func selectMode(_ newMode: AppMode) {
        guard newMode != state.mode else { return }
        if newMode == .viewer, state.testerColumns != .detailOnly {
            withAnimation(.smooth) { state.testerColumns = .detailOnly }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(280))
                state.mode = .viewer
            }
        } else {
            state.mode = newMode
        }
    }
}
