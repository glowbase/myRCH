import SwiftUI
import WebKit

// MARK: - Discover

/// RCH News and the Kids and Teen Health Info fact sheets, laid out like the
/// Health app's All Content: categories to browse, a Spotlight of the latest
/// news, then a few from each category with Show All.
struct DiscoverView: View {
    @State private var store = RCHContentStore.shared
    @State private var searchText = ""

    var body: some View {
        ScrollView {
            if searchText.isEmpty {
                VStack(alignment: .leading, spacing: 32) {
                    categories
                    spotlight
                    newsSection
                    ForEach(FactSheet.Library.allCases) { factSheetSection($0) }
                    Text("From The Royal Children's Hospital website. For advice about your child, talk to their care team.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
                .padding()
            } else {
                DiscoverSearchResults(query: searchText)
                    .padding()
            }
        }
        // Room past the closing note, so the tab bar and bottom search field
        // don't sit over it at the end of the scroll.
        .contentMargins(.bottom, 40, for: .scrollContent)
        .background(Color(.systemBackground))
        .navigationTitle("Discover")
        .searchable(text: $searchText, prompt: "Search news and fact sheets")
        .refreshable { await store.refresh(minimumInterval: 0) }
        .task { await store.loadNews() }
        .task {
            for library in FactSheet.Library.allCases { _ = try? await store.loadFactSheets(library) }
        }
    }

    // MARK: Browse by category

    private var categories: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Browse by Category")
                .font(.title3.bold())
                .padding(.horizontal, 4)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(NewsCategory.allCases) { category in
                        NavigationLink { NewsListView(category: category) } label: {
                            CategoryChip(title: category.title, systemImage: category.systemImage,
                                         color: category.color)
                        }
                    }
                    ForEach(FactSheet.Library.allCases) { library in
                        NavigationLink { FactSheetListView(library: library) } label: {
                            CategoryChip(title: library.title, systemImage: library.systemImage,
                                         color: library.color)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .scrollClipDisabled()
        }
    }

    // MARK: Spotlight

    @ViewBuilder
    private var spotlight: some View {
        VStack(alignment: .leading, spacing: 0) {
            DiscoverSectionHeader(title: "Spotlight")
            if store.isOffline {
                Label(store.newsSavedAt.map { "Offline. Showing the copy saved \($0.formatted(.relative(presentation: .named)))." }
                      ?? "Offline. Showing the saved copy.",
                      systemImage: "wifi.slash")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 8)
            }
            if store.latestNews.isEmpty {
                placeholder(error: store.newsError)
            } else {
                ForEach(Array(store.latestNews.prefix(2).enumerated()), id: \.element.id) { index, post in
                    if index > 0 { Divider() }
                    NavigationLink { NewsArticleView(post: post) } label: {
                        SpotlightCard(post: post)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Sections

    private var newsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            DiscoverSectionHeader(title: "RCH News", systemImage: NewsCategory.news.systemImage,
                                  color: NewsCategory.news.color) {
                NewsListView(category: .news)
            }
            if store.latestNews.isEmpty, store.newsError == nil {
                skeletonRows(3)
            }
            ForEach(Array(store.latestNews.dropFirst(2).prefix(3).enumerated()), id: \.element.id) { index, post in
                if index > 0 { Divider().padding(.leading, 80) }
                NavigationLink { NewsArticleView(post: post) } label: {
                    ContentRow(post: post)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func factSheetSection(_ library: FactSheet.Library) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            DiscoverSectionHeader(title: library.title, systemImage: library.systemImage, color: library.color) {
                FactSheetListView(library: library)
            }
            // Kids: the site's top five most-visited; Teen: featured sheets.
            let featured = store.discoverSheets(library)
            if let caption = store.topVisitedCaption(library) {
                Label(caption, systemImage: "chart.line.uptrend.xyaxis")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 4)
            }
            if featured.isEmpty {
                if store.factSheetErrors[library] != nil {
                    Label("Couldn't load \(library.title). Pull down to try again.", systemImage: "wifi.exclamationmark")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 12)
                } else {
                    skeletonRows(3)
                }
            }
            ForEach(Array(featured.enumerated()), id: \.element.id) { index, sheet in
                if index > 0 { Divider().padding(.leading, 80) }
                NavigationLink { FactSheetArticleView(sheet: sheet) } label: {
                    ContentRow(sheet: sheet)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func skeletonRows(_ count: Int) -> some View {
        ForEach(0..<count, id: \.self) { index in
            if index > 0 { Divider().padding(.leading, 80) }
            ContentRow.placeholder
        }
    }

    @ViewBuilder
    private func placeholder(error: String?) -> some View {
        if let error {
            ContentUnavailableView("Couldn't load news", systemImage: "wifi.exclamationmark",
                                   description: Text(error))
        } else {
            SpotlightSkeleton()
        }
    }
}

// MARK: - Colours

extension NewsCategory {
    var color: Color {
        switch self {
        case .news: Theme.brand
        case .goodFridayAppeal: Theme.red
        case .mediaReleases: Theme.orange
        }
    }
}

extension FactSheet.Library {
    var color: Color {
        switch self {
        case .kids: Theme.green
        case .teens: Feature.testResults.accent
        }
    }
}

// MARK: - Building blocks

/// A capsule with a coloured icon, like Health's category buttons.
private struct CategoryChip: View {
    let title: String
    let systemImage: String
    let color: Color

    var body: some View {
        Label {
            Text(title).foregroundStyle(.primary)
        } icon: {
            Image(systemName: systemImage).foregroundStyle(color)
        }
        .font(.body.weight(.medium))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground), in: .capsule)
    }
}

/// A bold title over a hairline, with an optional icon and Show All.
private struct DiscoverSectionHeader<Destination: View>: View {
    let title: String
    var systemImage: String?
    var color: Color = Theme.brand
    var destination: (() -> Destination)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage).foregroundStyle(color)
                }
                Text(title)
                    .font(.title2.bold())
                Spacer()
                if let destination {
                    NavigationLink("Show All", destination: destination)
                        .font(.body)
                }
            }
            .padding(.horizontal, 4)
            Divider()
        }
        .padding(.bottom, 12)
    }
}

extension DiscoverSectionHeader where Destination == EmptyView {
    init(title: String) {
        self.title = title
        self.destination = nil
    }
}

extension DiscoverSectionHeader {
    init(title: String, systemImage: String, color: Color, @ViewBuilder destination: @escaping () -> Destination) {
        self.title = title
        self.systemImage = systemImage
        self.color = color
        self.destination = destination
    }
}

/// Spotlight: title, summary, then the image large.
private struct SpotlightCard: View {
    let post: NewsPost

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(post.title)
                .font(.title3.bold())
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
            Text(post.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            ArticleImage(url: post.imageURL, placeholder: NewsCategory.news.systemImage)
                .aspectRatio(16 / 10, contentMode: .fit)
                .clipShape(.rect(cornerRadius: Theme.cardRadius))
                .padding(.top, 8)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 4)
        .contentShape(.rect)
    }
}

/// The Spotlight card's shape while news loads.
private struct SpotlightSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Placeholder headline for the latest news")
                .font(.title3.bold())
            Text("Placeholder summary of the story, two lines long")
                .font(.subheadline)
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .fill(Color(.tertiarySystemFill))
                .aspectRatio(16 / 10, contentMode: .fit)
                .padding(.top, 8)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 4)
        .redacted(reason: .placeholder)
        .accessibilityHidden(true)
    }
}

/// An article's title and paragraphs, greyed out while it loads.
private struct ArticleSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Placeholder article title")
                .font(.title.bold())
            Text("Placeholder byline")
                .font(.subheadline)
            ForEach(0..<3, id: \.self) { _ in
                Text("Placeholder paragraph text that fills the width of the screen and runs onto several lines, the way an article's opening paragraph does.")
                    .font(.body)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .redacted(reason: .placeholder)
        .accessibilityLabel("Loading")
    }
}

/// A list row: a rounded thumbnail (or an icon tile for fact sheets, which
/// have no pictures), a bold title and a grey line under it.
struct ContentRow: View {
    let title: String
    let subtitle: String
    let imageURL: URL?
    let systemImage: String
    let color: Color

    init(post: NewsPost) {
        title = post.title
        subtitle = post.summary
        imageURL = post.thumbnailURL
        systemImage = NewsCategory.news.systemImage
        color = NewsCategory.news.color
    }

    init(sheet: FactSheet) {
        title = sheet.title
        // What it's about, cut to two lines; the library until it's saved.
        subtitle = RCHContentStore.shared.summary(for: sheet) ?? "\(sheet.library.title) fact sheet"
        imageURL = nil
        // Suggests the topic, e.g. a thermometer for fever.
        systemImage = sheet.systemImage
        color = sheet.library.color
    }

    /// Stand-in text for the loading skeleton; redact it where it's used.
    private init() {
        title = "Placeholder title for an article"
        subtitle = "Placeholder summary of the article"
        imageURL = nil
        systemImage = "doc.text.fill"
        color = .gray
    }

    /// A row-shaped skeleton, greyed out like the rest of the app's.
    static var placeholder: some View {
        ContentRow()
            .redacted(reason: .placeholder)
            .accessibilityHidden(true)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Group {
                if imageURL != nil {
                    ArticleImage(url: imageURL, placeholder: systemImage)
                } else {
                    Image(systemName: systemImage)
                        .font(.title2)
                        .foregroundStyle(color)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(color.opacity(0.14))
                }
            }
            .frame(width: 66, height: 66)
            .clipShape(.rect(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 4)
        .contentShape(.rect)
    }
}

/// A remote picture that fills its frame, with a tinted icon until it loads.
private struct ArticleImage: View {
    let url: URL?
    let placeholder: String

    var body: some View {
        Color(.tertiarySystemFill)
            .overlay {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        Image(systemName: placeholder)
                            .font(.title)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .clipped()
            .accessibilityHidden(true)
    }
}

// MARK: - Search

private struct DiscoverSearchResults: View {
    let query: String
    @State private var store = RCHContentStore.shared

    private var sheets: [FactSheet] {
        FactSheet.Library.allCases.flatMap { store.factSheets[$0] ?? [] }.filter { sheet in
            sheet.title.localizedStandardContains(query)
                || sheet.aliases.contains { $0.localizedStandardContains(query) }
        }
    }

    private var news: [NewsPost] {
        store.latestNews.filter { $0.title.localizedStandardContains(query) || $0.summary.localizedStandardContains(query) }
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            if !news.isEmpty {
                DiscoverSectionHeader(title: "News")
                ForEach(news) { post in
                    NavigationLink { NewsArticleView(post: post) } label: { ContentRow(post: post) }
                        .buttonStyle(.plain)
                    Divider().padding(.leading, 80)
                }
            }
            if !sheets.isEmpty {
                DiscoverSectionHeader(title: "Fact Sheets")
                    .padding(.top, news.isEmpty ? 0 : 20)
                ForEach(sheets.prefix(60)) { sheet in
                    NavigationLink { FactSheetArticleView(sheet: sheet) } label: { ContentRow(sheet: sheet) }
                        .buttonStyle(.plain)
                    Divider().padding(.leading, 80)
                }
            }
            if news.isEmpty && sheets.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
    }
}

// MARK: - Lists

/// Every post in a category, newest first, loading more near the end.
struct NewsListView: View {
    let category: NewsCategory

    @State private var posts: [NewsPost] = []
    @State private var page = 0
    @State private var reachedEnd = false
    @State private var isLoading = false
    @State private var failure: String?

    var body: some View {
        List {
            ForEach(posts) { post in
                NavigationLink { NewsArticleView(post: post) } label: { ContentRow(post: post) }
                    .onAppear { if post.id == posts.last?.id { Task { await loadMore() } } }
            }
            // A screenful of skeleton rows at first; one row when loading more.
            if isLoading {
                ForEach(0..<(posts.isEmpty ? 6 : 1), id: \.self) { _ in ContentRow.placeholder }
            }
        }
        .listStyle(.plain)
        .overlay {
            if posts.isEmpty, let failure {
                ContentUnavailableView("Couldn't load news", systemImage: "wifi.exclamationmark",
                                       description: Text(failure))
            }
        }
        .navigationTitle(category.title)
        .refreshable {
            posts = []; page = 0; reachedEnd = false
            await loadMore()
        }
        .task { if posts.isEmpty { await loadMore() } }
    }

    private func loadMore() async {
        guard !isLoading, !reachedEnd else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let next = try await RCHContent.news(page: page + 1, perPage: 20, category: category)
            page += 1
            reachedEnd = next.count < 20
            posts += next.filter { post in !posts.contains { $0.id == post.id } }
            failure = nil
        } catch {
            failure = error.localizedDescription
        }
    }
}

/// A library's sheets A–Z by letter, or by category like Browse, with a
/// switch at the top. Search covers every sheet, by name or alias.
struct FactSheetListView: View {
    let library: FactSheet.Library

    enum Mode: String, CaseIterable, Identifiable {
        case alphabetical = "A–Z"
        case categories = "Categories"
        var id: String { rawValue }
    }

    @State private var store = RCHContentStore.shared
    @State private var searchText = ""
    @State private var failure: String?
    /// Remembered between visits.
    @AppStorage("factSheetListMode") private var mode: Mode = .alphabetical

    private var categories: [FactSheetCategory] { store.categories[library] ?? [] }

    private var sheets: [FactSheet] {
        let all = store.factSheets[library] ?? []
        guard !searchText.isEmpty else { return all }
        return all.filter { sheet in
            sheet.title.localizedStandardContains(searchText)
                || sheet.aliases.contains { $0.localizedStandardContains(searchText) }
        }
    }

    private var byLetter: [(letter: String, sheets: [FactSheet])] {
        Dictionary(grouping: sheets) { String($0.title.prefix(1)).uppercased() }
            .map { ($0.key, $0.value) }
            .sorted { $0.letter < $1.letter }
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 2)

    var body: some View {
        Group {
            // Searching lists every match A–Z, whichever view is chosen.
            if mode == .categories, searchText.isEmpty, !categories.isEmpty {
                categoryGrid
            } else {
                alphabeticalList
            }
        }
        .overlay {
            if store.factSheets[library] == nil {
                if let failure {
                    ContentUnavailableView("Couldn't load fact sheets", systemImage: "wifi.exclamationmark",
                                           description: Text(failure))
                } else {
                    // Titles greyed out, the shape of the A–Z list.
                    List {
                        Section("A") {
                            ForEach(0..<10, id: \.self) { index in
                                Text(index.isMultiple(of: 2) ? "Placeholder fact sheet" : "Placeholder fact sheet title")
                            }
                        }
                    }
                    .redacted(reason: .placeholder)
                    .disabled(true)
                    .accessibilityHidden(true)
                }
            } else if sheets.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .navigationTitle(library.title)
        .searchable(text: $searchText, prompt: "Search \(library.title)")
        .task {
            do { try await store.loadFactSheets(library) } catch { failure = error.localizedDescription }
        }
    }

    /// The A–Z / Categories switch, only once the site's categories have
    /// loaded. It scrolls with the content, under the large title; pinned
    /// above it, its bar covered the title.
    @ViewBuilder
    private var modePicker: some View {
        if !categories.isEmpty, searchText.isEmpty {
            Picker("View", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }

    /// Cards side by side, like Browse.
    private var categoryGrid: some View {
        ScrollView {
            modePicker
                .padding(.horizontal)
                .padding(.top, 8)
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(categories) { category in
                    NavigationLink {
                        FactSheetCategoryView(category: category, library: library)
                    } label: {
                        CategoryTile(category: category, library: library)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }

    private var alphabeticalList: some View {
        List {
            if !categories.isEmpty, searchText.isEmpty {
                Section {
                    modePicker
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }
            }
            ForEach(byLetter, id: \.letter) { group in
                Section(group.letter) {
                    ForEach(group.sheets) { sheet in
                        NavigationLink { FactSheetArticleView(sheet: sheet) } label: {
                            FactSheetRow(sheet: sheet)
                        }
                    }
                }
            }
        }
    }
}

/// A category as a Browse-style card: its coloured icon above the name,
/// and how many pages it has.
private struct CategoryTile: View {
    let category: FactSheetCategory
    let library: FactSheet.Library

    var body: some View {
        let style = category.style(in: library)
        let count = category.sheets.count
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: style.symbol)
                .foregroundStyle(style.color)
                .font(.system(size: 30))
                .frame(height: 36, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                // Two lines for the longer ones ("Navigating the health
                // system"), with room kept so the cards stay level.
                Text(category.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
                Text("\(count) page\(count == 1 ? "" : "s")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: Theme.cardRadius))
        .contentShape(.rect(cornerRadius: Theme.cardRadius))
        .accessibilityElement(children: .combine)
    }
}

/// A fact sheet in a list: its topic icon in the library's colour, then
/// its title.
struct FactSheetRow: View {
    let sheet: FactSheet

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(sheet.title)
                // What it's about, from the saved copy, cut off after two lines.
                if let summary = RCHContentStore.shared.summary(for: sheet) {
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        } icon: {
            Image(systemName: sheet.systemImage)
                .foregroundStyle(sheet.library.color)
        }
    }
}

/// One category's sheets, A–Z.
struct FactSheetCategoryView: View {
    let category: FactSheetCategory
    let library: FactSheet.Library

    var body: some View {
        List {
            ForEach(category.sheets.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }) { sheet in
                NavigationLink { FactSheetArticleView(sheet: sheet) } label: {
                    FactSheetRow(sheet: sheet)
                }
            }
        }
        .navigationTitle(category.name)
    }
}

// MARK: - Reading

/// A news post in the app's own layout (see `NewsFormatter`), with an "At a
/// glance" summary written on device.
struct NewsArticleView: View {
    let post: NewsPost

    private struct Glance: Identifiable {
        let text: String
        var id: String { text }
    }

    @State private var plainText: String?
    /// By item, so the sheet gets the text it opened with (see
    /// `FactSheetArticleView`).
    @State private var glance: Glance?

    var body: some View {
        // The category's colour (RCH News, Media Releases, Good Friday
        // Appeal), as the light-mode shade the page is drawn in.
        let category = post.primaryCategory ?? .news
        let accent = UIColor(category.color).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        let offersGlance = OnDeviceAI.isSupported
        ArticleReader(title: post.title, shareURL: post.link,
                      onGlance: offersGlance ? { if let plainText { glance = Glance(text: plainText) } } : nil) {
            let formatted = NewsFormatter.format(post.contentHTML, heroURL: post.imageURL, accent: accent)
            plainText = formatted.plainText
            return NewsFormatter.page(post: post,
                                      category: .init(name: category.title, symbol: category.systemImage, color: accent),
                                      accent: accent, accentHex: accent.hexString, formatted: formatted,
                                      offersGlance: offersGlance)
        }
        .sheet(item: $glance) { glance in
            NewsGlanceSheet(post: post, text: glance.text)
        }
    }
}

/// A fact sheet in the app's own layout (see `FactSheetFormatter`), with an
/// "At a glance" summary written on device.
struct FactSheetArticleView: View {
    let sheet: FactSheet

    /// The summary to show, carrying the page's text with it.
    private struct Glance: Identifiable {
        let text: String
        var id: String { text }
    }

    /// The page's text, for the summary; set once it's loaded.
    @State private var plainText: String?
    @State private var glance: Glance?

    /// The first of the site's categories that lists this sheet, for the
    /// pill under the title.
    private var category: FactSheetFormatter.Category? {
        let store = RCHContentStore.shared
        guard let match = (store.categories[sheet.library] ?? []).first(where: { category in
            category.sheets.contains { $0.key == sheet.key }
        }) else { return nil }
        let style = match.style(in: sheet.library)
        return .init(name: match.name, symbol: style.symbol,
                     color: UIColor(style.color).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)))
    }

    var body: some View {
        // The library's colour, as the light-mode shade the page's icons and
        // tints are drawn in.
        let accent = UIColor(sheet.library.color).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        let offersGlance = OnDeviceAI.isSupported
        ArticleReader(title: sheet.title, shareURL: sheet.url,
                      onGlance: offersGlance ? { if let plainText { glance = Glance(text: plainText) } } : nil) {
            // The saved copy when there is one, so it opens offline.
            let body = try await RCHContentStore.shared.sheetHTML(sheet)
            let formatted = FactSheetFormatter.format(body, accent: accent)
            plainText = formatted.plainText
            return FactSheetFormatter.page(title: sheet.title, library: sheet.library, accent: accent,
                                           accentHex: accent.hexString, formatted: formatted,
                                           category: category, offersGlance: offersGlance)
        }
        // By item, so the sheet gets the text it opened with. With a Bool,
        // its content was built from an earlier redraw, before the text
        // loaded, and came up blank.
        .sheet(item: $glance) { glance in
            FactSheetGlanceSheet(sheet: sheet, text: glance.text)
        }
    }
}

/// Shows an article in the app's type and colours (dark mode included),
/// with JavaScript off. Tapped links open in Safari.
private struct ArticleReader: View {
    let title: String
    let shareURL: URL
    /// Opens an "At a glance" summary, from the toolbar or the page's own
    /// button. Nil for articles without one.
    var onGlance: (() -> Void)? = nil
    let loadHTML: () async throws -> String
    @Environment(\.openURL) private var openURL

    @State private var page: WebPage?
    @State private var failure: String?

    var body: some View {
        Group {
            if let page {
                // Inside the safe area: under the tab bar, the article's last
                // lines (e.g. "Please always seek the most recent advice")
                // were hidden behind it.
                WebView(page)
                    .webViewLinkPreviews(.disabled)
            } else if let failure {
                ContentUnavailableView {
                    Label("Couldn't open article", systemImage: "doc.questionmark")
                } description: {
                    Text(failure)
                } actions: {
                    Button("Open in Safari") { openURL(shareURL) }
                }
            } else {
                ArticleSkeleton()
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let onGlance, page != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("At a Glance", systemImage: "sparkles", action: onGlance)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: shareURL)
            }
        }
        .task { await load() }
    }

    private func load() async {
        do {
            let html = try await loadHTML()
            var configuration = WebPage.Configuration()
            configuration.defaultNavigationPreferences.allowsContentJavaScript = false
            let decider = SafariLinkDecider(openURL: openURL, onGlance: onGlance)
            let page = WebPage(configuration: configuration, navigationDecider: decider)
            // The site as base URL, so its relative images and links work.
            page.load(html: html, baseURL: RCHContent.site)
            self.page = page
        } catch {
            failure = error.localizedDescription
        }
    }
}

private struct SafariLinkDecider: WebPage.NavigationDeciding {
    let openURL: OpenURLAction
    var onGlance: (() -> Void)? = nil

    mutating func decidePolicy(for action: WebPage.NavigationAction,
                               preferences: inout WebPage.NavigationPreferences) async -> WKNavigationActionPolicy {
        if action.navigationType == .linkActivated, let url = action.request.url {
            // The page's "At a glance" button opens the summary in the app.
            if url.scheme == FactSheetGlance.linkURL.scheme {
                onGlance?()
            } else {
                openURL(url)
            }
            return .cancel
        }
        return .allow
    }
}

// MARK: - Home

/// Home's Articles section, like the Health app's: the latest news, then
/// Show All Content, which opens Discover.
struct HomeArticlesSection: View {
    @State private var store = RCHContentStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Articles")
                    .font(.title2.bold())
                    .foregroundStyle(Theme.ink)
                Divider()
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 4)
            if store.latestNews.isEmpty, store.newsError == nil {
                ContentRow.placeholder
                Divider().padding(.leading, 84)
                ContentRow.placeholder
            }
            ForEach(Array(store.latestNews.prefix(2).enumerated()), id: \.element.id) { index, post in
                if index > 0 { Divider().padding(.leading, 84) }
                NavigationLink { NewsArticleView(post: post) } label: { ContentRow(post: post) }
                    .buttonStyle(.plain)
            }
            NavigationLink { DiscoverView() } label: {
                HStack(spacing: 14) {
                    Image(systemName: "text.below.photo.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.brand)
                        .frame(width: 30)
                    Text("Show All Content")
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: Theme.cardRadius))
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
        .task { await store.loadNews() }
    }
}
