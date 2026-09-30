import Foundation
import Observation

// MARK: - Models

/// A post from RCH News (blogs.rch.org.au/news).
nonisolated struct NewsPost: Identifiable, Hashable, Sendable {
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
nonisolated struct FactSheet: Identifiable, Hashable, Sendable {
    enum Library: String, CaseIterable, Identifiable, Sendable {
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
            URLQueryItem(name: "_fields", value: "id,date_gmt,link,title,excerpt,content,_links,_embedded")
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
                            contentHTML: content.rendered)
        }
    }

    // MARK: Fact sheets

    /// Every sheet in a library, A–Z, with its aliases folded in.
    @concurrent
    static func factSheets(_ library: Library) async throws -> [FactSheet] {
        let (data, _) = try await URLSession.shared.data(from: library.indexURL)
        let html = String(decoding: data, as: UTF8.self)
        // The letter tabs; the rest of the page links to other things.
        guard let start = html.range(of: "tabnav-letter-blocks") else { return [] }
        let pattern = "<li><a href=['\"](\(NSRegularExpression.escapedPattern(for: library.pathPrefix))[^'\"]+)['\"]>(.*?)</a></li>"
        var sheets: [URL: FactSheet] = [:]
        var aliases: [(title: String, url: URL)] = []
        for match in HTMLText.matches(pattern, in: String(html[start.lowerBound...])) {
            guard let url = URL(string: match[0], relativeTo: site)?.absoluteURL else { continue }
            let text = HTMLText.plain(match[1])
            // "Acne (see >> Pimples and skin health)"
            if let see = text.range(of: " (see") {
                aliases.append((String(text[..<see.lowerBound]), url))
            } else {
                sheets[url] = FactSheet(title: text, url: url, library: library)
            }
        }
        for alias in aliases {
            sheets[alias.url]?.aliases.append(alias.title)
        }
        return sheets.values.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    typealias Library = FactSheet.Library

    /// The sheet's own content: from under its title to the "seek the most
    /// recent advice" line, without the site's menus, scripts or
    /// translation buttons.
    @concurrent
    static func factSheetHTML(_ sheet: FactSheet) async throws -> String {
        let (data, _) = try await URLSession.shared.data(from: sheet.url)
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

/// Discover's content, loaded once and kept for the session. It isn't a
/// child's record, so it's the same for everyone and survives switching.
@Observable
final class RCHContentStore {
    static let shared = RCHContentStore()

    private(set) var latestNews: [NewsPost] = []
    private(set) var factSheets: [FactSheet.Library: [FactSheet]] = [:]
    private(set) var newsError: String?

    private var loadedAt: Date?

    /// Latest news, reloaded if older than 30 minutes.
    func loadNews(force: Bool = false) async {
        if !force, let loadedAt, Date.now.timeIntervalSince(loadedAt) < 30 * 60, !latestNews.isEmpty { return }
        do {
            latestNews = try await RCHContent.news()
            newsError = nil
            loadedAt = .now
        } catch {
            if latestNews.isEmpty { newsError = error.localizedDescription }
        }
    }

    func loadFactSheets(_ library: FactSheet.Library) async throws {
        guard factSheets[library] == nil else { return }
        factSheets[library] = try await RCHContent.factSheets(library)
    }

    func featured(_ library: FactSheet.Library) -> [FactSheet] {
        let sheets = factSheets[library] ?? []
        return library.featuredPaths.compactMap { path in
            sheets.first { $0.url.path.removingPercentEncoding?.contains("/\(path)/") == true
                           || $0.url.path.contains("/\(path)/") }
        }
    }
}
