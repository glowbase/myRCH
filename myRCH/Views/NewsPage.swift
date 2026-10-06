import SwiftUI
import UIKit

// MARK: - Formatting

/// Lays out an RCH News post like the fact sheets: title (no photo above
/// it), chips, then the story with a larger opening
/// paragraph, styled quotes, photo galleries as a grid and videos as
/// links. Shares the fact sheets' styling (`FactSheetFormatter.css`).
nonisolated enum NewsFormatter {
    struct Result {
        var html: String
        /// The story as plain text, for the AI summary and reading time.
        var plainText: String
    }

    static func format(_ content: String, heroURL: URL?, accent: UIColor) -> Result {
        var html = content
        // The blog's inline styles and Word leftovers (data-* attributes,
        // empty spans), and fixed sizes that made pages scroll sideways.
        for pattern in [#"\sstyle="[^"]*""#, #"\sdata-[a-z-]+="[^"]*""#, #"\s(?:width|height|sizes)="[^"]*""#,
                        #"<span>\s*</span>"#, #"<br[^>]*clear[^>]*>"#] {
            html = html.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }
        html = removingHeroCopy(html, heroURL: heroURL)
        html = videoLinks(html)
        // Gallery thumbnails and lightbox links: the full picture, in place.
        html = html.replacingOccurrences(
            of: #"<a[^>]*href="([^"]+\.(?:jpe?g|png|webp|gif))"[^>]*>\s*<img[^>]*>\s*</a>"#,
            with: "<img src=\"$1\" alt=\"\">", options: [.regularExpression, .caseInsensitive])
        // Empty paragraphs the blog uses for spacing.
        html = html.replacingOccurrences(of: #"<p[^>]*>(?:\s|&nbsp;|<br\s*/?>)*</p>"#, with: "",
                                         options: [.regularExpression, .caseInsensitive])
        let plainText = MyChartWebService.plainText(fromHTML: html)

        html = leadParagraph(html)
        html = quotes(html, accent: accent)
        html = FactSheetFormatter.replacing(#"<h2[^>]*>(.*?)</h2>"#, in: html) { groups in
            let (symbol, color) = FactSheetFormatter.headingStyle(HTMLText.plain(groups[1]).lowercased(), accent: accent)
            return "<h2><img class=\"hicon\" src=\"\(SymbolImage.tile(symbol, color: color))\" alt=\"\">\(groups[1])</h2>"
        }
        return Result(html: html, plainText: plainText)
    }

    /// Posts often start with the post's featured photo (the one on its
    /// Discover card). The page leaves it out, so it doesn't just move from
    /// above the title to straight under it.
    private static func removingHeroCopy(_ html: String, heroURL: URL?) -> String {
        guard let heroURL else { return html }
        // "Pelvic-Pain-Hero-400x224.jpg" and "Pelvic-Pain-Hero.jpg" are the same picture.
        func base(_ name: String) -> String {
            (name as NSString).deletingPathExtension
                .replacingOccurrences(of: #"-\d+x\d+$"#, with: "", options: .regularExpression).lowercased()
        }
        let hero = base(heroURL.lastPathComponent)
        guard let first = HTMLText.matches(#"(<img[^>]*src="([^"]+)"[^>]*>)"#, in: html).first,
              let src = URL(string: first[1]), base(src.lastPathComponent) == hero,
              let range = html.range(of: first[0]) else { return html }
        var html = html
        html.removeSubrange(range)
        return html
    }

    /// Embedded videos can't play with scripts off, so YouTube and Vimeo
    /// ones become a card that opens the video; other embeds are dropped.
    private static func videoLinks(_ html: String) -> String {
        let play = SymbolImage.tile("play.fill", color: .systemRed)
        let chevron = SymbolImage.glyph("chevron.right", color: .systemGray2, size: 14)
        return FactSheetFormatter.replacing(#"<iframe[^>]*src="([^"]+)"[^>]*>(?:.*?</iframe>)?"#, in: html) { groups in
            guard let watch = watchURL(forEmbed: groups[1]) else { return "" }
            return """
                <a class="glance video" href="\(watch.absoluteString)">
                <img class="hicon" src="\(play)" alt="">
                <span><b>Watch the video</b><small>Opens \(watch.host()?.contains("vimeo") == true ? "on Vimeo" : "on YouTube")</small></span>
                <img class="chevron" src="\(chevron)" alt="">
                </a>
                """
        }
    }

    private static func watchURL(forEmbed source: String) -> URL? {
        let source = source.hasPrefix("//") ? "https:" + source : source
        guard let url = URL(string: source), let host = url.host()?.lowercased() else { return nil }
        let id = url.lastPathComponent
        if host.contains("youtube") { return URL(string: "https://www.youtube.com/watch?v=\(id)") }
        if host.contains("vimeo") { return URL(string: "https://vimeo.com/\(id)") }
        return nil
    }

    /// The first real paragraph, a little larger, as a standfirst.
    private static func leadParagraph(_ html: String) -> String {
        guard let match = HTMLText.matches(#"(<p>)(.*?)</p>"#, in: html)
                .first(where: { HTMLText.plain($0[1]).count >= 60 }),
              let range = html.range(of: match[0] + match[1]) else { return html }
        var html = html
        html.replaceSubrange(range, with: "<p class=\"lead\">" + match[1])
        return html
    }

    /// Paragraphs that open with a quotation get a quote mark and italics.
    private static func quotes(_ html: String, accent: UIColor) -> String {
        let mark = SymbolImage.glyph("quote.opening", color: accent, size: 18)
        return FactSheetFormatter.replacing(#"<p>(\s*(?:<[^>]+>\s*)*[“"])"#, in: html) { groups in
            "<p class=\"quote\"><img class=\"qmark\" src=\"\(mark)\" alt=\"\">\(groups[1])"
        }
    }

    // MARK: Page

    struct Category {
        var name: String
        var symbol: String
        var color: UIColor
    }

    static func page(post: NewsPost, category: Category?, accent: UIColor, accentHex: String,
                     formatted: Result) -> String {
        let escape = FactSheetFormatter.escape
        // Discover-style chips: category, date, then reading time.
        var chips = ""
        if let category {
            chips += "<span class=\"chip\">\(SymbolImage.chipIcon(category.symbol, color: category.color))\(escape(category.name))</span>"
        }
        let date = post.date.formatted(date: .long, time: .omitted)
        chips += "<span class=\"chip\">\(SymbolImage.chipIcon("calendar", color: .secondaryLabel))\(escape(date))</span>"
        let words = formatted.plainText.split(whereSeparator: \.isWhitespace).count
        let minutes = max(1, Int((Double(words) / 200).rounded()))
        chips += "<span class=\"chip\">\(SymbolImage.chipIcon("clock", color: .secondaryLabel))\(minutes) min read</span>"

        return """
        <!doctype html><html><head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>\(FactSheetFormatter.css(accentHex: accentHex))\(css)</style></head><body>
        <header>
        <h1 class="title">\(escape(post.title))</h1>
        <div class="chips">\(chips)</div>
        </header>
        <article class="news">\(formatted.html)</article>
        <p class="source">From RCH News, published \(escape(date)).</p>
        </body></html>
        """
    }

    /// News additions to the shared styling.
    private static let css = """
        .news p { margin: 0.75em 0; }
        .lead { font-size: 1.12em; line-height: 1.5; font-weight: 500; }
        .quote { position: relative; padding-left: 30px; font-style: italic; }
        .qmark { position: absolute; left: 2px; top: 3px; width: 18px; height: 18px; }
        .news img { border-radius: 14px; display: block; margin: 12px 0; }
        .news .qmark { margin: 0; border-radius: 0; }
        .news .hicon { margin: 0; border-radius: 8px; }
        .gallery { display: grid; grid-template-columns: 1fr 1fr; gap: 8px; margin: 16px 0; }
        .gallery .row, .gallery [class*="col-"], .gallery br { display: contents; }
        .gallery img { width: 100%; aspect-ratio: 1; object-fit: cover; margin: 0; border-radius: 12px; }
        .video { margin: 14px 0; }
        blockquote { margin: 1em 0; padding: 12px 16px; border-radius: 16px; background: var(--card); font-style: italic; }
        """
}

// MARK: - At a glance

/// An on-device summary of a news post.
enum NewsGlance {
    static let instructions = """
        You are summarising a news story from The Royal Children's Hospital \
        for a parent. Use only what the story says; don't add details, \
        opinions or advice it doesn't contain.
        """

    private static let textLimit = 6_000

    static func brief(for post: NewsPost, text: String) -> AIBrief {
        let context = "News story: \(post.title)\nPublished: \(post.date.formatted(date: .long, time: .omitted))\n\nStory text:\n"
            + OnDeviceAI.clip(text, to: textLimit)
        return AIBrief(context: context, sections: [
            AISection(title: "In short", systemImage: "text.alignleft",
                      request: "In two or three short sentences, summarise what this story is about. Reply with only the summary."),
            AISection(title: "Key points", systemImage: "checklist",
                      request: "Now list the three to five most important points from the story, one per line starting with \"- \". Keep each to one short sentence. Reply with only the list."),
            AISection(title: "What it means for families", systemImage: "figure.2.and.child.holdinghands",
                      request: "Now, in one to three short sentences, say what this story means for families of children at the hospital, such as a new service, a change, or how to get help, if the story says. If it doesn't affect families directly, say so in one sentence. Reply with only the explanation."),
        ])
    }
}

struct NewsGlanceSheet: View {
    let post: NewsPost
    let text: String

    var body: some View {
        AIExplainSheet(heading: post.title, navigationTitle: "At a Glance", instructions: NewsGlance.instructions) {
            NewsGlance.brief(for: post, text: text)
        }
    }
}
