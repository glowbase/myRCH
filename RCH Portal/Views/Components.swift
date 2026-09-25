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

// MARK: - Skeleton loading

/// A rounded grey bar used to stand in for a line of text while loading.
struct SkeletonBar: View {
    var width: CGFloat? = nil
    var height: CGFloat = 12

    var body: some View {
        RoundedRectangle(cornerRadius: height / 2, style: .continuous)
            .fill(Color.gray.opacity(0.25))
            .frame(width: width, height: height)
    }
}

/// A placeholder row mirroring the shape of a typical list row.
struct SkeletonListRow: View {
    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(Color.gray.opacity(0.25))
                .frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 8) {
                SkeletonBar(width: 190, height: 13)
                SkeletonBar(width: 130, height: 11)
            }
            Spacer()
        }
        .padding(.vertical, 8)
        .shimmering()
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

/// A soft left-to-right highlight sweep, applied to skeleton shapes.
struct Shimmer: ViewModifier {
    @State private var move = false

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { geo in
                    let w = geo.size.width
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [.clear, .white.opacity(0.75), .clear],
                                startPoint: .leading, endPoint: .trailing))
                        .frame(width: w * 0.45)
                        .offset(x: move ? w * 1.3 : -w * 0.6)
                        .blendMode(.plusLighter)
                }
                .allowsHitTesting(false)
            }
            .mask(content)
            .onAppear {
                withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) {
                    move = true
                }
            }
    }
}

extension View {
    /// Adds an animated shimmer sweep — use on skeleton placeholder shapes.
    func shimmering() -> some View { modifier(Shimmer()) }
}

// MARK: - Async loading wrapper

/// Loading / empty / content phases for a screen backed by an async load.
enum LoadState<Value> {
    case loading
    case loaded(Value)
    case failed(String)
}

/// Runs `load` on first appearance and renders the appropriate state, showing
/// a shimmering skeleton while loading.
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
