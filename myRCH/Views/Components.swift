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

/// A capsule with a coloured icon, like Health's category buttons: Discover's
/// categories and Home's diagnoses and allergies. `background` suits the
/// screen behind it (Home's grouped grey needs the grouped card colour).
struct CategoryChip: View {
    let title: String
    let systemImage: String
    let color: Color
    var background = Color(.secondarySystemBackground)

    var body: some View {
        Label {
            Text(title).foregroundStyle(.primary)
        } icon: {
            Image(systemName: systemImage).foregroundStyle(color)
        }
        .font(.body.weight(.medium))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(background, in: .capsule)
    }
}

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
    @Environment(Session.self) private var session
    @Environment(\.scenePhase) private var scenePhase

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
        .task { await reload() }
        // Pull to refresh skips the cache; the spinner shows progress, so the
        // current content stays on screen.
        .refreshable {
            await session.refreshData()
            await reload()
        }
        // Back from the background: the cache answers if the data is under
        // five minutes old, otherwise this fetches fresh data.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await reload() } }
        }
    }

    /// Replaces the content only on success, so a failed background refresh
    /// doesn't wipe a screen that's already showing data.
    private func reload() async {
        do {
            state = .loaded(try await load())
        } catch {
            if case .loaded = state { return }
            state = .failed(error.localizedDescription)
        }
    }
}

/// A Health app–style summary card: the category's icon and name in its
/// colour at the top left, a date and chevron at the top right, and the main
/// content (a bold title or value) underneath.
struct SummaryCard<Content: View>: View {
    let category: String
    let systemImage: String
    let color: Color
    var detail: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Label(category, systemImage: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(color)
                Spacer(minLength: 8)
                if let detail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: Theme.cardRadius))
        .contentShape(.rect(cornerRadius: Theme.cardRadius))
    }
}

/// A Health-style section heading: large and bold, with an optional
/// "Show All" link.
struct SummarySectionHeader<Destination: Hashable>: View {
    let title: String
    var destination: Destination?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title2.bold())
                .foregroundStyle(Theme.ink)
            Spacer()
            if let destination {
                NavigationLink(value: destination) {
                    Text("Show All")
                        .font(.subheadline.weight(.medium))
                }
            }
        }
        .padding(.horizontal, 4)
    }
}

/// Turns the screen to full brightness while the view is on screen, like a
/// Wallet pass, and puts it back on leaving or when the app goes to the
/// background.
private struct FullBrightness: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @State private var saved: CGFloat?

    private var screen: UIScreen? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?.screen
    }

    func body(content: Content) -> some View {
        content
            .onAppear(perform: brighten)
            .onDisappear(perform: restore)
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { brighten() } else { restore() }
            }
    }

    private func brighten() {
        guard saved == nil, let screen else { return }
        saved = screen.brightness
        screen.brightness = 1
    }

    private func restore() {
        guard let saved else { return }
        screen?.brightness = saved
        self.saved = nil
    }
}

extension View {
    func fullBrightness() -> some View { modifier(FullBrightness()) }
}

/// "12345678" → "1 2 3 4 5 6 7 8", so VoiceOver reads digits, not a number.
func spokenDigits(_ number: String) -> String {
    number.map(String.init).joined(separator: " ")
}

extension View {
    /// Shows a `SummaryCard` as a list row: no row background or insets, so
    /// the card's own rounded background sits on the grouped list.
    func summaryCardRow() -> some View {
        listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            .listRowBackground(Color.clear)
    }
}
