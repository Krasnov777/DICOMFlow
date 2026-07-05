import SwiftUI

// MARK: - Header for each tool/detail pane

public struct ToolHeader: View {
    let title: String
    let subtitle: String?
    let symbol: String

    public init(_ title: String, subtitle: String? = nil, symbol: String) {
        self.title = title; self.subtitle = subtitle; self.symbol = symbol
    }

    public var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: symbol)
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Theme.accent)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.title2.bold())
                if let subtitle {
                    Text(subtitle).font(.callout).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }
}

// MARK: - Content card

public struct Card<Content: View>: View {
    let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }
    public var body: some View {
        content
            .padding(Theme.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md)
                .strokeBorder(.separator, lineWidth: 0.5))
    }
}

// MARK: - Status pill

public enum PillState { case ok, warn, error, neutral
    var color: Color {
        switch self { case .ok: .green; case .warn: .orange; case .error: .red; case .neutral: .secondary }
    }
}

public struct StatusPill: View {
    let text: String
    let state: PillState
    let symbol: String?
    public init(_ text: String, state: PillState = .neutral, symbol: String? = nil) {
        self.text = text; self.state = state; self.symbol = symbol
    }
    public var body: some View {
        HStack(spacing: 5) {
            if let symbol {
                Image(systemName: symbol).font(.caption2)
            } else {
                Circle().fill(state.color).frame(width: 7, height: 7)
            }
            Text(text).font(.caption.weight(.medium))
        }
        .foregroundStyle(state == .neutral ? AnyShapeStyle(.secondary) : AnyShapeStyle(state.color))
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, 4)
        .glassEffect(.regular, in: .capsule)
    }
}

// MARK: - Empty state

public struct EmptyState: View {
    let symbol: String
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?

    public init(symbol: String, title: String, message: String,
                actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.symbol = symbol; self.title = title; self.message = message
        self.actionTitle = actionTitle; self.action = action
    }

    public var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(message)
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.glassProminent)
            }
        }
    }
}

public extension View {
    /// Tooltip + VoiceOver label in one — use on icon-only controls.
    func hint(_ text: String) -> some View {
        help(text).accessibilityLabel(text)
    }
}
