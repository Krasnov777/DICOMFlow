import SwiftUI

/// Collapsible DIMSE activity console at the bottom of the tester.
struct LogConsole: View {
    @ObservedObject private var log = LogStore.shared
    @Binding var expanded: Bool

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "terminal").foregroundStyle(.secondary)
                Text("Activity").font(.subheadline.weight(.medium))
                if let last = log.lines.last, !expanded {
                    Text(last.text).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button { log.clear() } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless).hint("Clear")
                Button { withAnimation(.smooth) { expanded.toggle() } } label: {
                    Image(systemName: expanded ? "chevron.down" : "chevron.up")
                }.buttonStyle(.borderless).hint(expanded ? "Collapse activity log" : "Expand activity log")
            }
            .padding(.horizontal, Theme.Spacing.md).padding(.vertical, 6)

            if expanded {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(log.lines) { line in
                                HStack(spacing: 6) {
                                    Image(systemName: line.level.symbol)
                                        .font(.caption2).foregroundStyle(line.level.color)
                                    Text(line.text).font(.caption.monospaced())
                                    Spacer()
                                }
                                .id(line.id)
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.md).padding(.vertical, 4)
                    }
                    .frame(height: 150)
                    .onChange(of: log.lines.count) { _, _ in
                        if let last = log.lines.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                    }
                }
            }
        }
        .background(.bar)
    }
}
