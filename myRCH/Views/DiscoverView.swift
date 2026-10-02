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
        .background(Color(.systemBackground))
        .navigationTitle("Discover")
        .searchable(text: $searchText, prompt: "Search news and fact sheets")
        .refreshable { await store.loadNews(force: true) }
        .task { await store.loadNews() }
        .task {
            for library in FactSheet.Library.allCases { try? await store.loadFactSheets(library) }
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
            let featured = store.featured(library)
            if featured.isEmpty {
                ProgressView().frame(maxWidth: .infinity, minHeight: 80)
            }
            ForEach(Array(featured.prefix(3).enumerated()), id: \.element.id) { index, sheet in
                if index > 0 { Divider().padding(.leading, 80) }
                NavigationLink { FactSheetArticleView(sheet: sheet) } label: {
                    ContentRow(sheet: sheet)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func placeholder(error: String?) -> some View {
        if let error {
            ContentUnavailableView("Couldn't load news", systemImage: "wifi.exclamationmark",
                                   description: Text(error))
        } else {
            ProgressView().frame(maxWidth: .infinity, minHeight: 200)
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
        subtitle = "\(sheet.library.title) fact sheet"
        imageURL = nil
        systemImage = "doc.text.fill"
        color = sheet.library.color
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
            if isLoading {
                ProgressView().frame(maxWidth: .infinity)
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

/// A library's sheets A–Z, by letter, searchable by name or alias.
struct FactSheetListView: View {
    let library: FactSheet.Library

    @State private var store = RCHContentStore.shared
    @State private var searchText = ""
    @State private var failure: String?

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

    var body: some View {
        List {
            ForEach(byLetter, id: \.letter) { group in
                Section(group.letter) {
                    ForEach(group.sheets) { sheet in
                        NavigationLink(sheet.title) { FactSheetArticleView(sheet: sheet) }
                    }
                }
            }
        }
        .overlay {
            if store.factSheets[library] == nil {
                if let failure {
                    ContentUnavailableView("Couldn't load fact sheets", systemImage: "wifi.exclamationmark",
                                           description: Text(failure))
                } else {
                    ProgressView()
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
}

// MARK: - Reading

struct NewsArticleView: View {
    let post: NewsPost

    var body: some View {
        ArticleReader(title: post.title, shareURL: post.link) {
            ArticlePage.html(title: post.title,
                             byline: post.date.formatted(date: .long, time: .omitted),
                             heroURL: post.imageURL, body: post.contentHTML)
        }
    }
}

struct FactSheetArticleView: View {
    let sheet: FactSheet

    var body: some View {
        ArticleReader(title: sheet.title, shareURL: sheet.url) {
            let body = try await RCHContent.factSheetHTML(sheet)
            return ArticlePage.html(title: sheet.title, byline: "\(sheet.library.title) fact sheet",
                                    heroURL: nil, body: body)
        }
    }
}

/// Shows an article in the app's type and colours (dark mode included),
/// with JavaScript off. Tapped links open in Safari.
private struct ArticleReader: View {
    let title: String
    let shareURL: URL
    let loadHTML: () async throws -> String
    @Environment(\.openURL) private var openURL

    @State private var page: WebPage?
    @State private var failure: String?

    var body: some View {
        Group {
            if let page {
                WebView(page)
                    .webViewLinkPreviews(.disabled)
                    .ignoresSafeArea(edges: .bottom)
            } else if let failure {
                ContentUnavailableView {
                    Label("Couldn't open article", systemImage: "doc.questionmark")
                } description: {
                    Text(failure)
                } actions: {
                    Button("Open in Safari") { openURL(shareURL) }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
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
            let page = WebPage(configuration: configuration, navigationDecider: SafariLinkDecider(openURL: openURL))
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

    mutating func decidePolicy(for action: WebPage.NavigationAction,
                               preferences: inout WebPage.NavigationPreferences) async -> WKNavigationActionPolicy {
        if action.navigationType == .linkActivated, let url = action.request.url {
            openURL(url)
            return .cancel
        }
        return .allow
    }
}

nonisolated enum ArticlePage {
    /// Wraps an article body in a page styled like the app.
    static func html(title: String, byline: String, heroURL: URL?, body: String) -> String {
        let hero = heroURL.map { "<img class=\"hero\" src=\"\($0.absoluteString)\" alt=\"\">" } ?? ""
        return """
        <!doctype html><html><head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        :root { color-scheme: light dark; --brand: #219EBD; }
        body { font: -apple-system-body; font-family: -apple-system, sans-serif; line-height: 1.5;
               margin: 0; padding: 12px 20px 48px; -webkit-text-size-adjust: 100%; }
        h1.title { font-size: 1.75em; line-height: 1.2; margin: 8px 0 4px; }
        .byline { color: gray; font-size: 0.9em; margin-bottom: 16px; }
        .hero { width: 100%; border-radius: 16px; margin-bottom: 16px; }
        h1, h2, h3 { line-height: 1.25; }
        h2 { font-size: 1.3em; margin-top: 1.6em; }
        a { color: var(--brand); }
        img, video, iframe { max-width: 100%; height: auto; border-radius: 12px; }
        figure { margin: 16px 0; }
        figcaption { color: gray; font-size: 0.85em; }
        table { border-collapse: collapse; width: 100%; display: block; overflow-x: auto; }
        th, td { border: 1px solid rgba(128,128,128,0.35); padding: 6px 8px; text-align: left; }
        ul, ol { padding-left: 1.3em; }
        @media (prefers-color-scheme: dark) { :root { --brand: #62C7E0; } }
        </style></head><body>
        <h1 class="title">\(escape(title))</h1>
        <div class="byline">\(escape(byline))</div>
        \(hero)
        \(body)
        </body></html>
        """
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
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
