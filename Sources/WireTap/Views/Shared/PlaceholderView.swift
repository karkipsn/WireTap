import SwiftUI

/// A cross-platform/version compatible placeholder view.
/// Uses ContentUnavailableView on iOS 17+, and a custom fallback on older versions.
struct PlaceholderView: View {
    let title: String
    let systemImage: String
    let description: String

    var body: some View {
        if #available(iOS 17.0, *) {
            ContentUnavailableView(title, systemImage: systemImage, description: Text(description))
        } else {
            // Fallback for iOS < 17
            VStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
