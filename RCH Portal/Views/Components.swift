import SwiftUI

/// Circular initials avatar used for patient / linked accounts.
struct AvatarView: View {
    var initials: String
    var tint: Color = Theme.brand
    var size: CGFloat = 32

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(tint, in: .circle)
            .accessibilityHidden(true)
    }
}

// MARK: - Pills

/// A small tinted capsule label, e.g. for diagnoses and allergies.
struct Pill: View {
    let text: String
    var systemImage: String? = nil
    var tint: Color = Theme.brand

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage).font(.caption2.weight(.bold))
            }
            Text(text).font(.footnote.weight(.semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tint.opacity(0.14), in: .capsule)
    }
}

/// Lays subviews out left-to-right, wrapping onto new rows as needed.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, width: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            width = max(width, x + size.width)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Skeleton loading

/// A placeholder row mirroring the shape of a typical list row. The text is
/// never shown — `.redacted(reason: .placeholder)` renders it as skeleton bars.
struct SkeletonListRow: View {
    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(Color.gray.opacity(0.25))
                .frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 6) {
                Text("Placeholder row title text")
                    .font(.subheadline.weight(.semibold))
                Text("Placeholder detail")
                    .font(.caption)
            }
            Spacer()
        }
        .padding(.vertical, 8)
        .redacted(reason: .placeholder)
    }
}

/// A list-shaped skeleton used while a screen's data loads.
struct SkeletonList: View {
    var rows = 7

    var body: some View {
        List {
            ForEach(0..<rows, id: \.self) { _ in
                SkeletonListRow()
            }
        }
        .listStyle(.plain)
        .disabled(true)
        .allowsHitTesting(false)
    }
}

// MARK: - Async loading wrapper

/// Loading / empty / content phases for a screen backed by an async load.
enum LoadState<Value> {
    case loading
    case loaded(Value)
    case failed(String)
}

/// Runs `load` on first appearance and renders the appropriate state, showing
/// a redacted skeleton while loading.
struct AsyncSection<Value, Content: View>: View {
    let load: () async throws -> Value
    @ViewBuilder let content: (Value) -> Content

    @State private var state: LoadState<Value> = .loading

    var body: some View {
        Group {
            switch state {
            case .loading:
                SkeletonList()
            case let .loaded(value):
                content(value)
            case let .failed(message):
                ContentUnavailableView("Something went wrong", systemImage: "exclamationmark.triangle", description: Text(message))
            }
        }
        .task {
            do { state = .loaded(try await load()) }
            catch { state = .failed(error.localizedDescription) }
        }
    }
}
