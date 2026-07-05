import SwiftUI
import UniformTypeIdentifiers

/// "Wireshark for DICOM" (self-traffic): a decoded timeline of this app's
/// association negotiation + DIMSE messages, captured from DCMTK's protocol log.
struct ProtocolInspectorView: View {
    @ObservedObject private var log = ProtocolLog.shared
    @State private var search = ""
    @State private var pdusOnly = false
    @State private var autoScroll = true
    @State private var showPcapImporter = false
    @State private var importError: String?
    @State private var importNote: String?

    private var filtered: [ProtocolLog.Event] {
        log.events.filter { e in
            if pdusOnly && e.kind == .other { return false }
            if !search.isEmpty {
                return e.message.localizedCaseInsensitiveContains(search)
                    || e.kind.rawValue.localizedCaseInsensitiveContains(search)
            }
            return true
        }
    }

    struct Group: Identifiable { let id: Int; let events: [ProtocolLog.Event] }

    /// Filtered events split into association groups (group 0 = before any RQ).
    /// Single pass with a running bucket — appending into a copied array per
    /// event was O(n²) at the 3000-event cap.
    private var groups: [Group] {
        var out: [Group] = []
        var bucket: [ProtocolLog.Event] = []
        var currentID = Int.min
        for e in filtered {
            if e.group != currentID {
                if !bucket.isEmpty { out.append(Group(id: currentID, events: bucket)) }
                bucket = []
                currentID = e.group
            }
            bucket.append(e)
        }
        if !bucket.isEmpty { out.append(Group(id: currentID, events: bucket)) }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            ToolHeader("Protocol Inspector",
                       subtitle: "Decoded view of this app's DICOM traffic (associations + DIMSE)",
                       symbol: "waveform.path.ecg")

            HStack(spacing: Theme.Spacing.md) {
                TextField("Filter…", text: $search)
                    .textFieldStyle(.roundedBorder).frame(maxWidth: 240)
                Toggle("PDUs & DIMSE only", isOn: $pdusOnly).toggleStyle(.checkbox)
                Toggle("Verbose", isOn: $log.verbose).toggleStyle(.checkbox)
                    .help("dcmnet at DEBUG — full A-ASSOCIATE / DIMSE PDU dumps")
                Toggle("Auto-scroll", isOn: $autoScroll).toggleStyle(.checkbox)
                Spacer()
                Text("\(filtered.count)/\(log.events.count)").font(.callout).foregroundStyle(.secondary)
                Button { showPcapImporter = true } label: { Image(systemName: "square.and.arrow.down.on.square") }
                    .buttonStyle(.borderless).hint("Import a .pcap / .pcapng capture")
                Button { copyAll() } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.borderless).hint("Copy").disabled(filtered.isEmpty)
                Button { export() } label: { Image(systemName: "square.and.arrow.down") }
                    .buttonStyle(.borderless).hint("Export…").disabled(log.events.isEmpty)
                Button(role: .destructive) { log.clear() } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless).hint("Clear").disabled(log.events.isEmpty)
            }

            if let importError {
                Label(importError, systemImage: "xmark.octagon").foregroundStyle(.red).font(.callout)
            } else if let importNote {
                Label(importNote, systemImage: "square.and.arrow.down").foregroundStyle(.secondary).font(.callout)
            }

            if log.events.isEmpty {
                EmptyState(symbol: "waveform.path.ecg", title: "No traffic captured yet",
                           message: "Run a C-ECHO, C-STORE, or Query/Retrieve (or start the Test SCP). "
                               + "The association negotiation and DIMSE messages appear here, decoded — "
                               + "or import a .pcap/.pcapng capture with the ⬇︎ button above.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 4, pinnedViews: [.sectionHeaders]) {
                            ForEach(groups, id: \.id) { g in
                                Section {
                                    ForEach(g.events) { EventRow(event: $0) }
                                } header: {
                                    if g.id > 0 { AssociationHeader(group: g) }
                                }
                            }
                            Color.clear.frame(height: 1).id("bottom")
                        }
                        .padding(.vertical, 4)
                    }
                    .onChange(of: log.events.count) { _, _ in
                        if autoScroll { withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            }
        }
        .fileImporter(isPresented: $showPcapImporter,
                      allowedContentTypes: [.data, .item], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first { importPcap(url) }
        }
    }

    private func importPcap(_ url: URL) {
        importError = nil; importNote = nil
        _ = url.startAccessingSecurityScopedResource()
        defer { url.stopAccessingSecurityScopedResource() }
        do {
            let data = try Data(contentsOf: url)
            let pdus = try PcapParser.parse(data)
            log.importPDUs(pdus)
            importNote = "Imported \(pdus.count) PDU(s) from \(url.lastPathComponent)."
        } catch {
            importError = "Import failed: \(error.localizedDescription)"
        }
    }

    private func text() -> String {
        filtered.map { e in
            "[\(e.time.formatted(date: .omitted, time: .standard))] [\(e.kind.rawValue)]\n\(e.message)"
        }.joined(separator: "\n\n")
    }

    private func copyAll() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text(), forType: .string)
    }

    private func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "dicom-protocol.log"
        panel.allowedContentTypes = [.log, .plainText]
        if panel.runModal() == .OK, let url = panel.url {
            try? text().write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

/// Sticky section header for one association.
private struct AssociationHeader: View {
    let group: ProtocolInspectorView.Group
    private var subtitle: String {
        // Prefer the decoded A-ASSOCIATE-RQ title ("… CALLING → CALLED …").
        group.events.first(where: { $0.kind == .associateRQ })
            .map { $0.title.replacingOccurrences(of: "A-ASSOCIATE-RQ", with: "").trimmingCharacters(in: .whitespaces) }
            ?? ""
    }
    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "link").font(.caption2)
            Text("Association \(group.id)").font(.caption.weight(.bold))
            if !subtitle.isEmpty {
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            if let t = group.events.first?.time {
                Text(t, format: .dateTime.hour().minute().second())
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, Theme.Spacing.md).padding(.vertical, 4)
        .background(.bar, in: RoundedRectangle(cornerRadius: Theme.Radius.chip))
    }
}

private struct EventRow: View {
    let event: ProtocolLog.Event
    @State private var expanded = false
    private var multiline: Bool { event.message.contains("\n") }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: Theme.Spacing.sm) {
                Text(event.time, format: .dateTime.hour().minute().second())
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                if !event.direction.isEmpty {
                    Text(event.direction)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(event.direction == "→" ? .blue : .green)
                }
                Text(event.kind.rawValue)
                    .font(.caption2.weight(.bold)).foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(event.kind.color, in: Capsule())
                Text(event.title).font(.callout).lineLimit(expanded ? nil : 1)
                Spacer(minLength: 0)
                if multiline {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { if multiline { withAnimation(.smooth) { expanded.toggle() } } }

            if expanded {
                Text(event.message)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.Spacing.sm)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: Theme.Radius.chip))
            }
        }
        .padding(.horizontal, Theme.Spacing.md).padding(.vertical, 6)
        .background(event.kind.color.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }
}
