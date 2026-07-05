import SwiftUI

enum TesterTool: String, CaseIterable, Identifiable {
    case echo = "C-ECHO"
    case store = "C-STORE"
    case queryRetrieve = "Query / Retrieve"
    case worklist = "Worklist"
    case negotiate = "Negotiation Probe"
    case dicomweb = "DICOMweb"
    case fhir = "FHIR"
    case hl7 = "HL7 (MLLP)"
    case scp = "Test SCP"
    case protocolInspector = "Protocol Inspector"
    case tags = "Tag Inspector"
    case editor = "Tag Editor"
    case anonymize = "Anonymizer"
    case validator = "Validator"
    case diff = "Compare"
    case generator = "Generator"
    case dicomdir = "DICOMDIR"
    case dump = "Dump"
    case redact = "Redact Pixels"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .echo: return "dot.radiowaves.left.and.right"
        case .store: return "paperplane"
        case .queryRetrieve: return "magnifyingglass"
        case .worklist: return "calendar.badge.clock"
        case .negotiate: return "checklist"
        case .dicomweb: return "globe"
        case .fhir: return "waveform.path"
        case .hl7: return "arrow.left.arrow.right"
        case .scp: return "antenna.radiowaves.left.and.right"
        case .protocolInspector: return "waveform.path.ecg"
        case .tags: return "tag"
        case .editor: return "pencil"
        case .anonymize: return "person.crop.circle.badge.xmark"
        case .validator: return "checkmark.shield"
        case .diff: return "arrow.left.and.right.square"
        case .generator: return "wand.and.stars"
        case .dicomdir: return "opticaldiscdrive"
        case .dump: return "curlybraces.square"
        case .redact: return "eye.slash"
        }
    }
}

/// Tester / Toolbench: sidebar of DICOM tools.
public struct TesterRootView: View {
    @EnvironmentObject var appState: AppState
    @State private var tool: TesterTool = .echo
    @StateObject private var target = TesterTarget()
    @Binding var columnVisibility: NavigationSplitViewVisibility

    public init(columnVisibility: Binding<NavigationSplitViewVisibility>) {
        self._columnVisibility = columnVisibility
    }

    public var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $tool) {
                Section("Networking") {
                    ForEach([TesterTool.echo, .store, .queryRetrieve, .worklist, .negotiate, .dicomweb, .fhir, .hl7, .scp, .protocolInspector]) { row($0) }
                }
                Section("Files & Tags") {
                    ForEach([TesterTool.tags, .editor, .anonymize, .validator, .diff, .generator, .dicomdir, .dump, .redact]) { row($0) }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
            // Replace the system sidebar toggle with our own so we control the
            // animation timing — a snappier reveal cuts the number of frames the
            // detail has to reflow in a narrow (tiled) window, so the lag there
            // is much less noticeable.
            .toolbar(removing: .sidebarToggle)
        } detail: {
            VStack(spacing: 0) {
                ScrollView {
                    detail
                        .environmentObject(target)
                        .padding(Theme.Spacing.xl)
                        .frame(maxWidth: 760, alignment: .leading)
                        // Fill the viewport height (top-anchored, centered
                        // horizontally) so empty states can center vertically.
                        // containerRelativeFrame(.vertical) depends only on the
                        // container's HEIGHT, so it doesn't re-measure on every
                        // frame of the horizontal sidebar open/close animation
                        // (the GeometryReader it replaced did → visible hitch).
                        .frame(maxWidth: .infinity, alignment: .top)
                        .containerRelativeFrame(.vertical, alignment: .top)
                }
                LogConsole(expanded: $logExpanded)
            }
        }
        // Viewer → "Send to PACS" handoff: jump to the C-STORE tool. Checked on
        // appear too — the mode switch sets pendingStorePaths *before* this view
        // exists, so onChange alone would miss it.
        .task(id: appState.pendingStorePaths) {
            if appState.pendingStorePaths != nil { tool = .store }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    withAnimation(.snappy(duration: 0.22)) {
                        columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .help("Toggle sidebar")
                .accessibilityLabel("Toggle sidebar")
            }
        }
    }

    @State private var logExpanded = false

    private func row(_ t: TesterTool) -> some View {
        Label(t.rawValue, systemImage: t.symbol)
            .tag(t)
    }

    @ViewBuilder
    private var detail: some View {
        switch tool {
        case .echo: EchoView()
        case .store: StoreView()
        case .queryRetrieve: QueryRetrieveView()
        case .worklist: WorklistView()
        case .negotiate: NegotiationView()
        case .dicomweb: DicomWebView()
        case .fhir: FHIRView()
        case .hl7: HL7View()
        case .scp: LocalSCPView()
        case .protocolInspector: ProtocolInspectorView()
        case .tags: TagInspectorView()
        case .editor: TagEditorView()
        case .anonymize: AnonymizeView()
        case .validator: ValidatorView()
        case .diff: DiffView()
        case .generator: GeneratorView()
        case .dicomdir: DicomDirView()
        case .dump: DumpView()
        case .redact: RedactView()
        }
    }
}
