import SwiftUI

// MARK: - InfoBlock

/// A labelled value block with optional copy + share.
public struct InfoBlock: View {
    let title: String
    let content: String
    var mono: Bool = false
    var tint: Color = .primary

    public init(title: String, content: String, mono: Bool = false, tint: Color = .primary) {
        self.title = title
        self.content = content
        self.mono = mono
        self.tint = tint
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title.uppercased())
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                CopyButton(text: content)
                ShareButton(text: content)
            }
            Text(content)
                .font(mono ? .caption.monospaced() : .caption)
                .foregroundStyle(tint)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - CopyButton

public struct CopyButton: View {
    let text: String
    @State private var copied = false

    public init(text: String) { self.text = text }

    public var body: some View {
        Button {
            copyToPasteboard(text)
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.caption2)
                .foregroundStyle(copied ? .green : .secondary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - ShareButton

public struct ShareButton: View {
    let text: String

    public init(text: String) { self.text = text }

    public var body: some View {
        ShareLink(item: text) {
            Image(systemName: "square.and.arrow.up")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - FilterChip

public struct WireTapFilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    public init(label: String, isSelected: Bool, action: @escaping () -> Void) {
        self.label = label
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption2.bold())
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.1))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Pretty JSON helper

public func prettyJson(_ raw: String) -> String? {
    guard let data = raw.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data),
          let pretty = try? JSONSerialization.data(withJSONObject: obj, options: .prettyPrinted),
          let str = String(data: pretty, encoding: .utf8)
    else { return nil }
    return str
}

private func copyToPasteboard(_ text: String) {
    #if os(iOS)
    UIPasteboard.general.string = text
    #elseif os(macOS)
    let pasteboard = NSPasteboard.general
    pasteboard.declareTypes([.string], owner: nil)
    pasteboard.setString(text, forType: .string)
    #endif
}
