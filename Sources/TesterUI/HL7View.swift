import SwiftUI
import Network

/// An MLLP listener that receives HL7 messages and auto-ACKs each one.
@MainActor
final class HL7Listener: ObservableObject {
    struct Received: Identifiable {
        let id = UUID(); let time: Date; let message: String; let ack: String; let peer: String
        var summary: String { HL7.summary(message) }
    }
    @Published private(set) var running = false
    @Published private(set) var messages: [Received] = []
    @Published var port = 2575
    @Published var errorText: String?
    private var listener: NWListener?

    func toggle() { running ? stop() : start() }

    func start() {
        guard let raw = UInt16(exactly: port), let p = NWEndpoint.Port(rawValue: raw) else {
            errorText = "Invalid port (1–65535)"; return
        }
        do {
            let l = try NWListener(using: .tcp, on: p)
            l.newConnectionHandler = { [weak self] c in self?.accept(c) }
            l.stateUpdateHandler = { [weak self] st in
                Task { @MainActor in
                    switch st {
                    case .ready: self?.running = true; self?.errorText = nil
                    case .failed(let e): self?.errorText = e.localizedDescription; self?.running = false
                    case .cancelled: self?.running = false
                    default: break
                    }
                }
            }
            l.start(queue: .global()); listener = l
        } catch { errorText = error.localizedDescription }
    }
    func stop() { listener?.cancel(); listener = nil; running = false }
    func clear() { messages.removeAll() }

    nonisolated private func accept(_ conn: NWConnection) {
        conn.start(queue: .global())
        receive(conn, Data())
    }
    nonisolated private func receive(_ conn: NWConnection, _ acc: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, err in
            guard let self else { return }
            var acc2 = acc
            if let data { acc2.append(data) }
            while let fs = acc2.firstIndex(of: HL7.FS) {
                let msg = HL7.deframe(Data(acc2[acc2.startIndex..<fs]))
                var next = acc2.index(after: fs)
                if next < acc2.endIndex && acc2[next] == HL7.CR { next = acc2.index(after: next) }
                acc2 = Data(acc2[next...])
                let ack = HL7.buildACK(for: msg)
                let peer = "\(conn.endpoint)"
                conn.send(content: HL7.frame(ack), completion: .contentProcessed { _ in })
                Task { @MainActor in self.record(msg, ack: ack, peer: peer) }
            }
            if err == nil && !isComplete { self.receive(conn, acc2) } else { conn.cancel() }
        }
    }
    private func record(_ msg: String, ack: String, peer: String) {
        messages.insert(Received(time: Date(), message: msg, ack: ack, peer: peer), at: 0)
        if messages.count > 500 { messages.removeLast() }
    }
}

/// HL7 v2 over MLLP: send messages (with ACK) or run a listener.
struct HL7View: View {
    enum Mode: String, CaseIterable, Identifiable { case send = "Send", listen = "Listen"; var id: String { rawValue } }
    @State private var mode: Mode = .send

    @State private var host = "127.0.0.1"
    @State private var port = 2575
    @State private var message = HL7.fill(HL7.templates[0].message)
    @State private var ack: String?
    @State private var sendError: String?
    @State private var busy = false
    @StateObject private var listener = HL7Listener()

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            ToolHeader("HL7 (MLLP)", subtitle: "Send HL7 v2 messages or run an MLLP listener",
                       symbol: "arrow.left.arrow.right")
            Picker("Mode", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).frame(width: 220)

            if mode == .send { sendView } else { listenView }
        }
    }

    // MARK: Send

    private var sendView: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Card {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    HStack(spacing: Theme.Spacing.md) {
                        labeled("Host", $host).frame(maxWidth: .infinity)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Port").font(.caption).foregroundStyle(.secondary)
                            TextField("2575", value: $port, format: .number.grouping(.never))
                                .frame(width: 90).textFieldStyle(.roundedBorder)
                        }
                        Menu {
                            ForEach(Array(HL7.templates.enumerated()), id: \.offset) { _, t in
                                Button(t.name) { message = HL7.fill(t.message) }
                            }
                        } label: { Label("Template", systemImage: "doc.badge.plus") }
                        .menuStyle(.borderlessButton).fixedSize()
                        Button { runSend() } label: { Label("Send", systemImage: "paperplane") }
                            .buttonStyle(.glassProminent).disabled(busy)
                    }
                    TextEditor(text: $message)
                        .font(.system(.callout, design: .monospaced))
                        .frame(minHeight: 160)
                        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.chip).strokeBorder(.separator))
                    if busy { ProgressView().controlSize(.small) }
                    if let sendError { Label(sendError, systemImage: "xmark.octagon").foregroundStyle(.red) }
                }
            }
            if let ack {
                Card {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        StatusPill(ack.contains("|AA|") ? "ACK: Accepted (AA)"
                                   : ack.contains("|AE|") ? "ACK: Error (AE)"
                                   : ack.contains("|AR|") ? "ACK: Reject (AR)" : "ACK received",
                                   state: ack.contains("|AA|") ? .ok : .warn, symbol: "checkmark.seal")
                        HL7FieldTree(message: ack)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func runSend() {
        busy = true; ack = nil; sendError = nil
        let (h, p, m) = (host, port, message)
        Task {
            do { ack = try await HL7Client.send(host: h, port: p, message: m) }
            catch { sendError = error.localizedDescription }
            busy = false
        }
    }

    // MARK: Listen

    private var listenView: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Card {
                HStack(spacing: Theme.Spacing.md) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Listen Port").font(.caption).foregroundStyle(.secondary)
                        TextField("2575", value: $listener.port, format: .number.grouping(.never))
                            .frame(width: 90).textFieldStyle(.roundedBorder).disabled(listener.running)
                    }
                    if listener.running {
                        Button(role: .destructive) { listener.stop() } label: { Label("Stop", systemImage: "stop.fill") }
                            .buttonStyle(.glass)
                    } else {
                        Button { listener.start() } label: { Label("Start", systemImage: "play.fill") }
                            .buttonStyle(.glassProminent)
                    }
                    StatusPill(listener.running ? "Listening on \(listener.port) (auto-ACK)" : "Stopped",
                               state: listener.running ? .ok : .neutral,
                               symbol: listener.running ? "dot.radiowaves.left.and.right" : "pause.circle")
                    Spacer()
                    if !listener.messages.isEmpty {
                        Button { copyReceived() } label: { Image(systemName: "doc.on.doc") }
                            .buttonStyle(.borderless).hint("Copy all received messages")
                        Button(role: .destructive) { listener.clear() } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                    }
                }
            }
            if let e = listener.errorText {
                Card { Label(e, systemImage: "xmark.octagon").foregroundStyle(.red) }
            }
            if listener.messages.isEmpty {
                EmptyState(symbol: "tray", title: "No messages received",
                           message: "Start the listener, then send an HL7 message to this host on the chosen port.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(listener.messages) { MessageRow(item: $0) }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            }
        }
    }

    private func copyReceived() {
        let text = listener.messages.reversed().map { m in
            "# \(m.time.formatted(date: .omitted, time: .standard))  \(m.summary)  \(m.peer)\n"
                + m.message.replacingOccurrences(of: "\r", with: "\n")
        }.joined(separator: "\n\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func labeled(_ name: String, _ binding: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).font(.caption).foregroundStyle(.secondary)
            TextField(name, text: binding).textFieldStyle(.roundedBorder)
        }
    }
}

private struct MessageRow: View {
    let item: HL7Listener.Received
    @State private var expanded = false
    @State private var showRaw = false
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: Theme.Spacing.sm) {
                Text(item.time, format: .dateTime.hour().minute().second())
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Text(item.summary).font(.callout.weight(.medium))
                Text(item.peer).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.smooth) { expanded.toggle() } }
            if expanded {
                Picker("", selection: $showRaw) {
                    Text("Fields").tag(false)
                    Text("Raw").tag(true)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 140)
                if showRaw {
                    Text(item.message.replacingOccurrences(of: "\r", with: "\n"))
                        .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Theme.Spacing.sm)
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: Theme.Radius.chip))
                } else {
                    HL7FieldTree(message: item.message)
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.md).padding(.vertical, 6)
        .background(.background.secondary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// Structured segment/field view of an HL7 message (named fields where known).
struct HL7FieldTree: View {
    let message: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(HL7.parse(message)) { seg in
                VStack(alignment: .leading, spacing: 2) {
                    Text(seg.name)
                        .font(.caption.weight(.bold)).foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(.tint, in: RoundedRectangle(cornerRadius: 4))
                    ForEach(seg.fields) { f in
                        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                            Text(f.label).font(.caption.monospaced()).foregroundStyle(.secondary)
                                .frame(width: 56, alignment: .trailing)
                            Text(f.name).font(.caption).foregroundStyle(.secondary)
                                .frame(width: 170, alignment: .leading).lineLimit(1)
                            Text(f.value).font(.caption.monospaced()).textSelection(.enabled)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
        .padding(Theme.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: Theme.Radius.chip))
    }
}
