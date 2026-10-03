import CryptoKit
import Foundation
import Observation

// MARK: - Models

/// A post from RCH News (blogs.rch.org.au/news).
nonisolated struct NewsPost: Identifiable, Hashable, Sendable, Codable {
    let id: Int
    var title: String
    /// The post's excerpt as plain text.
    var summary: String
    var date: Date
    var link: URL
    /// Full size, for Spotlight and the article; medium, for list rows.
    var imageURL: URL?
    var thumbnailURL: URL?
    /// The post body as the blog renders it.
    var contentHTML: String
    /// The blog's category ids (see `NewsCategory`). Optional, so news saved
    /// before it was added still loads.
    var categories: [Int]? = nil

    /// The most specific category it's in: a media release or the Good
    /// Friday Appeal rather than plain news.
    var primaryCategory: NewsCategory? {
        let ids = Set(categories ?? [])
        return [NewsCategory.mediaReleases, .goodFridayAppeal, .news].first { ids.contains($0.rawValue) }
    }
}

/// The blog's categories worth browsing on their own.
nonisolated enum NewsCategory: Int, CaseIterable, Identifiable, Sendable {
    case news = 6
    case goodFridayAppeal = 7198
    case mediaReleases = 26963

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .news: "RCH News"
        case .goodFridayAppeal: "Good Friday Appeal"
        case .mediaReleases: "Media Releases"
        }
    }

    var systemImage: String {
        switch self {
        case .news: "newspaper.fill"
        case .goodFridayAppeal: "heart.fill"
        case .mediaReleases: "megaphone.fill"
        }
    }
}

/// A fact sheet from Kids Health Info or Teen Health Info.
nonisolated struct FactSheet: Identifiable, Hashable, Sendable, Codable {
    enum Library: String, CaseIterable, Identifiable, Sendable, Codable {
        case kids, teens

        var id: String { rawValue }

        var title: String {
            switch self {
            case .kids: "Kids Health Info"
            case .teens: "Teen Health Info"
            }
        }

        var systemImage: String {
            switch self {
            case .kids: "figure.and.child.holdinghands"
            case .teens: "figure.walk"
            }
        }

        /// The A–Z index page.
        var indexURL: URL {
            switch self {
            case .kids: URL(string: "https://www.rch.org.au/kidsinfo/fact_sheets/")!
            case .teens: URL(string: "https://www.rch.org.au/teeninfo/fact_sheets/")!
            }
        }

        /// Where the sheets live; the index also links elsewhere.
        var pathPrefix: String {
            switch self {
            case .kids: "/kidsinfo/fact_sheets/"
            case .teens: "/teeninfo/fact-sheets/"
            }
        }

        /// A few common ones to show before "Show All", by URL path.
        var featuredPaths: [String] {
            switch self {
            case .kids: ["Fever_in_children", "Croup", "Gastroenteritis_gastro", "Asthma", "Bronchiolitis"]
            case .teens: ["Mental_health_support_hub", "Screen_time_and_social_media", "Vaping_–_everything_you_need_to_know"]
            }
        }
    }

    var title: String
    var url: URL
    var library: Library
    /// Other names the index lists it under, e.g. "Acne" for "Pimples and
    /// skin health". Searchable, but not shown as their own rows.
    var aliases: [String] = []
    var id: URL { url }

    /// The URL's last part in lower case, e.g. "croup": the site links the
    /// same sheet with different capitalisation in different places.
    var key: String { url.lastPathComponent.lowercased() }
}

/// One of a library's categories, e.g. "Respiratory", as the site's
/// "View by Category" lists them.
nonisolated struct FactSheetCategory: Identifiable, Hashable, Sendable, Codable {
    var name: String
    var sheets: [FactSheet]
    var id: String { name }
}

/// Everything a library's index page lists.
nonisolated struct FactSheetIndex: Sendable {
    var sheets: [FactSheet]
    var categories: [FactSheetCategory]
    /// The site's "Top 10 visited" list, most visited first (Kids only).
    var topVisited: [FactSheet]
    /// The list's heading, e.g. "Top 10 visited Kids Health Info fact
    /// sheets in August 2026".
    var topVisitedHeading: String?
}

// MARK: - Loading

/// Reads RCH News through the blog's public WordPress API, and the fact
/// sheets from their A–Z pages (there's no feed, so this reads the HTML and
/// may need updating if the site changes).
nonisolated enum RCHContent {
    static let site = URL(string: "https://www.rch.org.au")!
    private static let newsAPI = "https://blogs.rch.org.au/news/wp-json/wp/v2/posts"

    // MARK: News

    @concurrent
    static func news(page: Int = 1, perPage: Int = 12, category: NewsCategory? = nil) async throws -> [NewsPost] {
        var components = URLComponents(string: newsAPI)!
        components.queryItems = [
            URLQueryItem(name: "per_page", value: String(perPage)),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "_embed", value: "wp:featuredmedia"),
            URLQueryItem(name: "_fields", value: "id,date_gmt,link,title,excerpt,content,categories,_links,_embedded")
        ]
        if let category {
            components.queryItems?.append(URLQueryItem(name: "categories", value: String(category.rawValue)))
        }
        let (data, response) = try await URLSession.shared.data(from: components.url!)
        // Past the last page, WordPress answers 400 rather than an empty list.
        if (response as? HTTPURLResponse)?.statusCode == 400 { return [] }
        return try JSONDecoder().decode([WPPost].self, from: data).compactMap(\.post)
    }

    private struct WPPost: Decodable {
        struct Rendered: Decodable { let rendered: String }
        struct Size: Decodable { let source_url: String }
        struct Details: Decodable { let sizes: [String: Size]? }
        struct Media: Decodable {
            let source_url: String?
            let media_details: Details?
        }
        struct Embedded: Decodable {
            let featuredMedia: [Media]?
            enum CodingKeys: String, CodingKey { case featuredMedia = "wp:featuredmedia" }
        }

        let id: Int
        let date_gmt: String
        let link: String
        let title: Rendered
        let excerpt: Rendered
        let content: Rendered
        let categories: [Int]?
        let _embedded: Embedded?

        private static let dateFormat: Date.ParseStrategy = .init(
            format: "\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits)T\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits):\(second: .twoDigits)",
            timeZone: .gmt)

        var post: NewsPost? {
            guard let link = URL(string: link) else { return nil }
            let media = _embedded?.featuredMedia?.first
            let image = media?.source_url.flatMap(URL.init(string:))
            let thumbnail = media?.media_details?.sizes?["medium"].flatMap { URL(string: $0.source_url) }
            // The excerpt ends with a "… Continued" link to the post.
            let summary = HTMLText.plain(excerpt.rendered)
                .replacingOccurrences(of: "Continued", with: "", options: [.anchored, .backwards])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return NewsPost(id: id, title: HTMLText.plain(title.rendered), summary: summary,
                            date: (try? Date(date_gmt, strategy: Self.dateFormat)) ?? .now,
                            link: link, imageURL: image, thumbnailURL: thumbnail ?? image,
                            contentHTML: content.rendered, categories: categories)
        }
    }

    // MARK: Fact sheets

    /// A library's index page: every sheet A–Z with its aliases folded in,
    /// the categories, and (for Kids) the top 10 visited.
    @concurrent
    static func factSheetIndex(_ library: Library) async throws -> FactSheetIndex {
        let (data, _) = try await URLSession.shared.data(from: library.indexURL)
        let html = String(decoding: data, as: UTF8.self)
        let sheets = factSheets(in: html, library: library)
        let byKey = Dictionary(sheets.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        let top = topVisited(in: html, library: library, byKey: byKey)
        return FactSheetIndex(sheets: sheets,
                              categories: categories(in: html, library: library, byKey: byKey),
                              topVisited: top.sheets, topVisitedHeading: top.heading)
    }

    /// The site's own sheet for a link, else one made from the link (a
    /// category can list a sheet the A–Z doesn't, or one from the other
    /// library).
    private static func sheet(href: String, title: String, library: Library,
                              byKey: [String: FactSheet]) -> FactSheet? {
        // One top-10 link reads "https://www.https://www.rch.org.au/…", so
        // only the fact sheet path is trusted.
        guard let path = HTMLText.matches(#"(/(?:kidsinfo/fact_sheets|teeninfo/fact-sheets)/[^/'"?#]+)"#,
                                          in: href).first?.first,
              let url = URL(string: path + "/", relativeTo: site)?.absoluteURL else { return nil }
        if let known = byKey[url.lastPathComponent.lowercased()] { return known }
        let title = HTMLText.plain(title)
        guard !title.isEmpty else { return nil }
        return FactSheet(title: title, url: url, library: path.hasPrefix("/teeninfo") ? .teens : library)
    }

    /// "View by Category": accordions of an `<h2>` name and a list of links.
    private static func categories(in html: String, library: Library,
                                   byKey: [String: FactSheet]) -> [FactSheetCategory] {
        guard let start = html.range(of: "class=\"cat-panel\"") else { return [] }
        let panel = String(html[start.lowerBound...])
        return HTMLText.matches(##"<h2><a href="#">(.*?)</a></h2>.*?<ul>(.*?)</ul>"##, in: panel).compactMap { match in
            let name = HTMLText.plain(match[0])
            var seen: Set<String> = []
            let sheets = HTMLText.matches(#"<li><a href=['"]([^'"]+)['"]>(.*?)</a></li>"#, in: match[1]).compactMap { link in
                sheet(href: link[0], title: link[1], library: library, byKey: byKey)
            }.filter { seen.insert($0.key).inserted }
            guard !name.isEmpty, !sheets.isEmpty else { return nil }
            return FactSheetCategory(name: name, sheets: sheets)
        }
    }

    /// The green "Top 10 visited … in <month>" box, in order.
    private static func topVisited(in html: String, library: Library,
                                   byKey: [String: FactSheet]) -> (sheets: [FactSheet], heading: String?) {
        guard let start = html.range(of: "Top 10 visited") else { return ([], nil) }
        let rest = html[start.lowerBound...]
        let end = rest.range(of: "<script")?.lowerBound ?? rest.endIndex
        let box = String(rest[..<end])
        let heading = box.range(of: "</h3>").map { HTMLText.plain(String(box[..<$0.lowerBound])) }
        var seen: Set<String> = []
        let sheets = HTMLText.matches(#"<a href="([^"]+)"[^>]*>(.*?)</a>"#, in: box).compactMap { link in
            sheet(href: link[0], title: link[1], library: library, byKey: byKey)
        }.filter { seen.insert($0.key).inserted }
        return (sheets, heading)
    }

    /// Every sheet in a library, A–Z, with its aliases folded in.
    private static func factSheets(in html: String, library: Library) -> [FactSheet] {
        // The letter tabs; the rest of the page links to other things.
        guard let start = html.range(of: "tabnav-letter-blocks") else { return [] }
        let pattern = "<li><a href=['\"](\(NSRegularExpression.escapedPattern(for: library.pathPrefix))[^'\"]+)['\"]>(.*?)</a></li>"
        var sheets: [URL: FactSheet] = [:]
        var aliases: [(title: String, url: URL)] = []
        for match in HTMLText.matches(pattern, in: String(html[start.lowerBound...])) {
            guard let url = URL(string: match[0], relativeTo: site)?.absoluteURL else { continue }
            let text = HTMLText.plain(match[1])
            // A cross-reference: "Acne (see >> Pimples and skin health)".
            // Some have no name before it (" (see >> …)", trimmed to
            // "(see >> …)"); those are skipped. Either way it never stands in
            // for the sheet itself, which is listed under its own name.
            if let see = text.range(of: "(see") {
                let alias = text[..<see.lowerBound].trimmingCharacters(in: .whitespaces)
                if !alias.isEmpty { aliases.append((alias, url)) }
            } else if !text.isEmpty, sheets[url] == nil {
                sheets[url] = FactSheet(title: text, url: url, library: library)
            }
        }
        for alias in aliases where sheets[alias.url]?.aliases.contains(alias.title) == false {
            sheets[alias.url]?.aliases.append(alias.title)
        }
        return sheets.values.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    typealias Library = FactSheet.Library

    /// The sheet's own content: from under its title to the "seek the most
    /// recent advice" line, without the site's menus, scripts or
    /// translation buttons.
    @concurrent
    static func factSheetHTML(_ sheet: FactSheet, session: URLSession = .shared) async throws -> String {
        let (data, _) = try await session.data(from: sheet.url)
        let page = String(decoding: data, as: UTF8.self)
        // The on-screen title; the app shows its own above the content.
        let titleEnd = page.range(of: "<h1 class=\"hidden-print\">").flatMap {
            page.range(of: "</h1>", range: $0.upperBound..<page.endIndex)
        }
        guard let start = titleEnd?.upperBound else { throw URLError(.cannotParseResponse) }
        var end = page.range(of: "<footer", range: start..<page.endIndex)?.lowerBound ?? page.endIndex
        if let advice = page.range(of: "Please always seek the most recent advice", range: start..<end),
           let close = page.range(of: "</p>", range: advice.upperBound..<end) {
            end = close.upperBound
        }
        var body = String(page[start..<end])
        for pattern in ["<script.*?</script>", "<style.*?</style>", "\\sstyle=\"[^\"]*\"",
                        "<a[^>]*class=\"btn[^\"]*\"[^>]*>.*?</a>"] {
            body = body.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        return body
    }
}

// MARK: - HTML text

nonisolated enum HTMLText {
    /// Tags removed, entities decoded and whitespace collapsed.
    static func plain(_ html: String) -> String {
        let text = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        return decodeEntities(text)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
        "hellip": "…", "ndash": "–", "mdash": "—", "rsquo": "’", "lsquo": "‘",
        "rdquo": "”", "ldquo": "“"
    ]

    static func decodeEntities(_ text: String) -> String {
        var result = ""
        var rest = Substring(text)
        while let amp = rest.firstIndex(of: "&") {
            result += rest[..<amp]
            guard let semi = rest[amp...].firstIndex(of: ";"),
                  rest.distance(from: amp, to: semi) <= 10 else {
                result += "&"
                rest = rest[rest.index(after: amp)...]
                continue
            }
            let name = rest[rest.index(after: amp)..<semi]
            var decoded: String?
            if name.hasPrefix("#x") || name.hasPrefix("#X") {
                decoded = UInt32(name.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String($0) }
            } else if name.hasPrefix("#") {
                decoded = UInt32(name.dropFirst()).flatMap(Unicode.Scalar.init).map { String($0) }
            } else {
                decoded = named[String(name)]
            }
            result += decoded ?? String(rest[amp...semi])
            rest = rest[rest.index(after: semi)...]
        }
        return result + rest
    }

    /// Capture groups of every match, in order.
    static func matches(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).map { match in
            (1..<match.numberOfRanges).map { i in
                Range(match.range(at: i), in: text).map { String(text[$0]) } ?? ""
            }
        }
    }
}

// MARK: - Store

/// Discover's content, with a copy saved on the iPhone so it works offline.
/// It isn't a child's record, so it's the same for everyone and survives
/// switching. News and the A–Z lists refresh each time the app opens; the
/// fact sheets themselves download over Wi-Fi and refresh every so often,
/// and any sheet that's opened refreshes then.
@Observable
final class RCHContentStore {
    static let shared = RCHContentStore()

    private(set) var latestNews: [NewsPost] = []
    private(set) var factSheets: [FactSheet.Library: [FactSheet]] = [:]
    /// Each library's categories, as the site's "View by Category" lists them.
    private(set) var categories: [FactSheet.Library: [FactSheetCategory]] = [:]
    /// The site's top 10 visited sheets, most visited first (Kids only).
    private(set) var topVisited: [FactSheet.Library: [FactSheet]] = [:]
    /// e.g. "Top 10 visited Kids Health Info fact sheets in August 2026".
    private(set) var topVisitedHeadings: [FactSheet.Library: String] = [:]
    private(set) var newsError: String?
    /// Why a library's list couldn't load, when there's no saved copy.
    private(set) var factSheetErrors: [FactSheet.Library: String] = [:]
    /// True when the last refresh couldn't reach the site and the saved
    /// copy is showing.
    private(set) var isOffline = false
    /// When news was last refreshed from the site.
    private(set) var newsSavedAt: Date?

    /// A post or sheet to open from a tapped notification.
    enum Link: Identifiable, Hashable {
        case post(Int)
        case sheet(URL)

        var id: String {
            switch self {
            case let .post(id): "post-\(id)"
            case let .sheet(url): url.absoluteString
            }
        }
    }

    /// Set when a Discover notification is tapped; RootView opens it.
    var openLink: Link?

    func post(id: Int) -> NewsPost? { latestNews.first { $0.id == id } }

    func sheet(url: URL) -> FactSheet? {
        FactSheet.Library.allCases.lazy.compactMap { self.factSheets[$0]?.first { $0.url == url } }.first
    }

    /// What a refresh found that wasn't there before, for notifications.
    /// Empty the first time, when there's nothing to compare against.
    struct Updates {
        var posts: [NewsPost] = []
        var sheets: [FactSheet] = []
    }

    private struct Saved: Codable {
        var news: [NewsPost] = []
        var newsSavedAt: Date?
        /// By library, e.g. "kids".
        var sheets: [String: [FactSheet]] = [:]
        /// When each sheet's page was last saved, by its URL.
        var sheetSavedAt: [String: Date] = [:]
        // Optional, so copies saved before these were added still load.
        var categories: [String: [FactSheetCategory]]?
        var topVisited: [String: [FactSheet]]?
        var topVisitedHeadings: [String: String]?
    }

    @ObservationIgnored private var sheetSavedAt: [String: Date] = [:]
    @ObservationIgnored private var newsLoadedAt: Date?
    @ObservationIgnored private var listsLoaded: Set<FactSheet.Library> = []
    @ObservationIgnored private var lastRefresh: Date?
    @ObservationIgnored private var isDownloading = false
    /// Short descriptions for lists, worked out from saved sheets as needed.
    @ObservationIgnored private var summaries: [URL: String] = [:]

    /// Opened sheets older than this refresh in the background.
    private static let openedSheetMaxAge: TimeInterval = 24 * 60 * 60
    /// The whole library is re-fetched this often: sheets rarely change, and
    /// there are hundreds, so not every visit.
    private static let librarySheetMaxAge: TimeInterval = 14 * 24 * 60 * 60

    /// Re-downloadable, so kept out of iCloud backups.
    @ObservationIgnored private let folder: URL = {
        var folder = URL.applicationSupportDirectory.appending(path: "Discover", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder.appending(path: "sheets"), withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? folder.setResourceValues(values)
        return folder
    }()

    private var indexURL: URL { folder.appending(path: "discover.json") }

    /// Fact sheets download only on Wi-Fi (not mobile data or Low Data Mode).
    private static let wifiSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.allowsExpensiveNetworkAccess = false
        configuration.allowsConstrainedNetworkAccess = false
        return URLSession(configuration: configuration)
    }()

    init() {
        guard let data = try? Data(contentsOf: indexURL),
              let saved = try? JSONDecoder().decode(Saved.self, from: data) else { return }
        latestNews = saved.news
        newsSavedAt = saved.newsSavedAt
        for library in FactSheet.Library.allCases {
            let key = library.rawValue
            if let sheets = saved.sheets[key] { factSheets[library] = sheets }
            if let list = saved.categories?[key] { categories[library] = list }
            if let top = saved.topVisited?[key] { topVisited[library] = top }
            if let heading = saved.topVisitedHeadings?[key] { topVisitedHeadings[library] = heading }
        }
        sheetSavedAt = saved.sheetSavedAt
    }

    // MARK: Refreshing

    /// Refreshes news and both A–Z lists, then carries on downloading fact
    /// sheets in the background. Called each time the app opens; skipped
    /// if it ran in the last few minutes.
    @discardableResult
    func refresh(minimumInterval: TimeInterval = 5 * 60, downloadsSheets: Bool = true) async -> Updates {
        if let lastRefresh, Date.now.timeIntervalSince(lastRefresh) < minimumInterval { return Updates() }
        lastRefresh = .now
        var updates = Updates()
        updates.posts = await loadNews(force: true)
        for library in FactSheet.Library.allCases {
            updates.sheets += (try? await loadFactSheets(library, force: true)) ?? []
        }
        if downloadsSheets { Task { await downloadLibraries() } }
        return updates
    }

    /// Latest news, reloaded if older than 30 minutes. Returns posts that
    /// are new since the last copy.
    @discardableResult
    func loadNews(force: Bool = false) async -> [NewsPost] {
        if !force, let newsLoadedAt, Date.now.timeIntervalSince(newsLoadedAt) < 30 * 60, !latestNews.isEmpty { return [] }
        do {
            let fresh = try await RCHContent.news()
            let known = Set(latestNews.map(\.id))
            // Newer than the oldest one already seen, so a post that drops
            // back into the latest few (e.g. after another's deleted) isn't new.
            let oldest = latestNews.map(\.date).min() ?? .distantFuture
            let added = fresh.filter { !known.contains($0.id) && $0.date >= oldest }
            latestNews = fresh
            newsError = nil
            isOffline = false
            newsLoadedAt = .now
            newsSavedAt = .now
            save()
            return added
        } catch {
            // Keep showing the saved copy; only an empty screen gets the error.
            if latestNews.isEmpty { newsError = error.localizedDescription } else { isOffline = true }
            return []
        }
    }

    /// A library's A–Z list, from the site once per session (or when
    /// forced), else the saved copy. Returns sheets new since the last copy.
    @discardableResult
    func loadFactSheets(_ library: FactSheet.Library, force: Bool = false) async throws -> [FactSheet] {
        if !force, listsLoaded.contains(library) { return [] }
        do {
            let index = try await RCHContent.factSheetIndex(library)
            let fresh = index.sheets
            // An empty list means the page changed shape; keep the saved one.
            guard !fresh.isEmpty else { return [] }
            let previous = factSheets[library] ?? []
            let known = Set(previous.map(\.url))
            let added = previous.isEmpty ? [] : fresh.filter { !known.contains($0.url) }
            factSheets[library] = fresh
            // Kept if this visit's page didn't have them, rather than lost.
            if !index.categories.isEmpty { categories[library] = index.categories }
            if !index.topVisited.isEmpty {
                topVisited[library] = index.topVisited
                topVisitedHeadings[library] = index.topVisitedHeading
            }
            factSheetErrors[library] = nil
            listsLoaded.insert(library)
            save()
            return added
        } catch {
            guard factSheets[library]?.isEmpty == false else {
                factSheetErrors[library] = error.localizedDescription
                throw error
            }
            isOffline = true
            return []
        }
    }

    // MARK: Fact sheet pages

    /// A sheet's content: the saved copy straight away (refreshed in the
    /// background if it's more than a day old), else from the site.
    func sheetHTML(_ sheet: FactSheet) async throws -> String {
        if let saved = savedHTML(sheet) {
            if isStale(sheet, maxAge: Self.openedSheetMaxAge) {
                Task { _ = try? await fetchSheet(sheet, session: .shared) }
            }
            return saved
        }
        return try await fetchSheet(sheet, session: .shared)
    }

    /// Saves every sheet in both libraries that's missing or due a refresh,
    /// four at a time, over Wi-Fi only. Stops after a run of failures (no
    /// Wi-Fi, or offline) and picks up again on a later visit.
    func downloadLibraries() async {
        guard !isDownloading else { return }
        isDownloading = true
        defer { isDownloading = false }
        let due = FactSheet.Library.allCases.flatMap { factSheets[$0] ?? [] }
            .filter { isStale($0, maxAge: Self.librarySheetMaxAge) }
        guard !due.isEmpty else { return }

        let session = Self.wifiSession
        var queue = due.makeIterator()
        var saved = 0
        var failuresInARow = 0
        await withTaskGroup(of: (FactSheet, String?).self) { group in
            func addNext() {
                guard let sheet = queue.next() else { return }
                group.addTask { (sheet, try? await RCHContent.factSheetHTML(sheet, session: session)) }
            }
            for _ in 0..<4 { addNext() }
            for await (sheet, html) in group {
                if let html {
                    store(html, for: sheet)
                    failuresInARow = 0
                    saved += 1
                    // The index isn't rewritten for every one of hundreds.
                    if saved.isMultiple(of: 25) { save() }
                } else {
                    failuresInARow += 1
                    if failuresInARow >= 5 {
                        group.cancelAll()
                        break
                    }
                }
                addNext()
            }
        }
        save()
    }

    private func fetchSheet(_ sheet: FactSheet, session: URLSession) async throws -> String {
        let html = try await RCHContent.factSheetHTML(sheet, session: session)
        store(html, for: sheet)
        save()
        return html
    }

    private func store(_ html: String, for sheet: FactSheet) {
        try? Data(html.utf8).write(to: fileURL(sheet), options: .atomic)
        sheetSavedAt[sheet.url.absoluteString] = .now
        summaries[sheet.url] = nil
    }

    /// A sentence or two about the sheet for lists, from its saved copy (e.g.
    /// "Croup is an infection caused by a virus…"). Nil until it's saved;
    /// the full libraries download in the background.
    func summary(for sheet: FactSheet) -> String? {
        if let summary = summaries[sheet.url] { return summary }
        guard let html = savedHTML(sheet), let summary = FactSheetFormatter.summary(fromBody: html) else { return nil }
        summaries[sheet.url] = summary
        return summary
    }

    private func savedHTML(_ sheet: FactSheet) -> String? {
        (try? Data(contentsOf: fileURL(sheet))).map { String(decoding: $0, as: UTF8.self) }
    }

    private func isStale(_ sheet: FactSheet, maxAge: TimeInterval) -> Bool {
        guard savedHTML(sheet) != nil, let date = sheetSavedAt[sheet.url.absoluteString] else { return true }
        return Date.now.timeIntervalSince(date) > maxAge
    }

    /// Named by a hash of the sheet's URL.
    private func fileURL(_ sheet: FactSheet) -> URL {
        let name = SHA256.hash(data: Data(sheet.url.absoluteString.utf8)).prefix(16)
            .map { String(format: "%02x", $0) }.joined()
        return folder.appending(path: "sheets/\(name).html")
    }

    private func save() {
        func byName<T>(_ values: [FactSheet.Library: T]) -> [String: T] {
            Dictionary(uniqueKeysWithValues: values.map { ($0.key.rawValue, $0.value) })
        }
        let saved = Saved(news: latestNews, newsSavedAt: newsSavedAt, sheets: byName(factSheets),
                          sheetSavedAt: sheetSavedAt, categories: byName(categories),
                          topVisited: byName(topVisited), topVisitedHeadings: byName(topVisitedHeadings))
        guard let data = try? JSONEncoder().encode(saved) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    /// The library's featured sheets, matched on the URL's last part (e.g.
    /// "Croup"; `URL.path` drops the trailing slash, so a "/Croup/" match
    /// never worked). If the site has renamed them, the first few A–Z, so
    /// the section is never left empty.
    func featured(_ library: FactSheet.Library) -> [FactSheet] {
        let sheets = factSheets[library] ?? []
        let matched = library.featuredPaths.compactMap { path in
            sheets.first { $0.url.lastPathComponent == path }
        }
        return matched.isEmpty ? Array(sheets.prefix(3)) : matched
    }

    /// What the Discover page lists for a library: the site's top five
    /// most-visited when it has them (Kids), else the featured sheets.
    func discoverSheets(_ library: FactSheet.Library) -> [FactSheet] {
        if let top = topVisited[library], !top.isEmpty { return Array(top.prefix(5)) }
        return Array(featured(library).prefix(3))
    }

    /// "Most visited in August 2026", from the top 10's heading.
    func topVisitedCaption(_ library: FactSheet.Library) -> String? {
        guard topVisited[library]?.isEmpty == false, let heading = topVisitedHeadings[library],
              let range = heading.range(of: " in ", options: .backwards) else { return nil }
        return "Most visited in \(heading[range.upperBound...])"
    }
}
