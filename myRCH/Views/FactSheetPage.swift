import SwiftUI
import UIKit

// MARK: - Formatting

/// Turns a fact sheet's content (as saved from the site) into the app's
/// own layout: the translated-resources block and the closing credits
/// gone, the review date lifted out for a pill, and colour and icons on
/// the parts that matter most: key points, 000 warnings, "When to get
/// help", and common questions.
nonisolated enum FactSheetFormatter {
    struct Result {
        /// The content, ready for `page(…)`.
        var html: String
        /// e.g. "June 2026", from "Reviewed June 2026".
        var reviewed: String?
        /// The cleaned content as plain text, for the AI summary.
        var plainText: String
    }

    static func format(_ body: String, accent: UIColor) -> Result {
        let reviewed = HTMLText.matches(#"Reviewed\s+([A-Z][a-z]+\s+\d{4})"#, in: HTMLText.plain(body)).first?.first

        var html = removingExtras(body)
        // "Developed by The Royal Children's Hospital…", the review date
        // and the disclaimer: all from here down.
        if let credit = html.range(of: "Developed by") ?? html.range(of: "Please always seek the most recent advice") {
            let start = html.range(of: "<p", options: .backwards, range: html.startIndex..<credit.lowerBound)?.lowerBound
                ?? credit.lowerBound
            html = String(html[..<start])
        }
        // Mentions of audio and video players the app doesn't show, and
        // empty leftovers.
        for pattern in [#"<p>[^<]*(?:podcast|audio format)[^<]*</p>"#, #"<ul[^>]*>\s*</ul>"#,
                        #"<p>(?:\s|&nbsp;|<br\s*/?>)*</p>"#] {
            html = html.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }
        let plainText = MyChartWebService.plainText(fromHTML: html)

        html = keyPoints(html, accent: accent)
        html = triageCards(html)
        html = urgentWarnings(html)
        html = sectionHeadings(html, accent: accent)
        html = questions(html, accent: accent)
        // Figure captions under pictures, however they're worded or styled.
        // (The CSS also treats any paragraph straight after a picture as one.)
        html = html.replacingOccurrences(of: #"<p>(\s*(?:<[^>]+>\s*)*(?:Figure|Image|Photo|Illustration|Source)\b)"#,
                                         with: "<p class=\"caption\">$1",
                                         options: [.regularExpression, .caseInsensitive])
        return Result(html: html, reviewed: reviewed, plainText: plainText)
    }

    /// What the site marks "rch-no-print" (the translated resources at the
    /// top, the podcast and video players near the end), any other embedded
    /// players, which can't play here with scripts off and only left blank
    /// space, and fixed widths that made the page scroll sideways.
    private static func removingExtras(_ body: String) -> String {
        var html = body
        // Some pages put the podcast and "For more information" in one such
        // block, or it runs past the saved text, so it can't be measured:
        // those keep their content and lose only the player inside.
        while let marker = html.range(of: "class=\"rch-no-print\"") {
            if let block = elementRange(around: marker.upperBound, tag: "div", in: html) {
                let content = html[block]
                if !content.contains("<h2") || content.contains("Translated resources") {
                    html.removeSubrange(block)
                    continue
                }
            }
            html.replaceSubrange(marker, with: "")
        }
        if let marker = html.range(of: "Translated resources") {
            html = removingElement(around: marker.lowerBound, tag: "div", in: html)
        }
        if let marker = html.range(of: "id=\"podcast-container\"") {
            html = removingElement(around: marker.upperBound, tag: "div", in: html)
        }
        for pattern in [#"<iframe.*?</iframe>"#, #"<iframe[^>]*/?>"#, #"<object.*?</object>"#, #"<embed[^>]*>"#,
                        #"<(audio|video).*?</\1>"#] {
            html = html.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }
        return html.replacingOccurrences(of: #"\s(?:width|height)="\d+%?""#, with: "", options: .regularExpression)
    }

    /// A short description for lists: the first real paragraph after the
    /// key points (e.g. under "What is croup?"), else the first key point.
    static func summary(fromBody body: String) -> String? {
        let html = removingExtras(body)
        let headings = HTMLText.matches(#"<h2[^>]*>(.*?)</h2>"#, in: html)
        for heading in headings where !HTMLText.plain(heading[0]).lowercased().contains("key points") {
            guard let range = html.range(of: heading[0]) else { continue }
            for paragraph in HTMLText.matches(#"<p[^>]*>(.*?)</p>"#, in: String(html[range.upperBound...])).prefix(4) {
                let text = HTMLText.plain(paragraph[0])
                if text.count >= 40 { return String(text.prefix(220)) }
            }
            break
        }
        return HTMLText.matches(#"<li[^>]*>(.*?)</li>"#, in: html)
            .map { HTMLText.plain($0[0]) }
            .first { $0.count >= 30 }
            .map { String($0.prefix(220)) }
    }

    // MARK: Sections

    /// The "Key points" box: a tinted card with a star heading and ticks.
    private static func keyPoints(_ html: String, accent: UIColor) -> String {
        guard let heading = html.range(of: "<h2>Key points</h2>") else { return html }
        var html = html
        let tile = SymbolImage.tile("star.fill", color: accent)
        html.replaceSubrange(heading, with: "<h2 class=\"keypoints-title\"><img class=\"hicon\" src=\"\(tile)\" alt=\"\">Key points</h2>")
        // The box is the <div> just before its heading.
        if let box = html.range(of: "<div", options: .backwards, range: html.startIndex..<heading.lowerBound) {
            html.replaceSubrange(box, with: "<div class=\"keypoints\"")
        }
        return html
    }

    /// "When to get help" is a table of level headings ("Call an ambulance
    /// (000) if:") each followed by a list. Each pair becomes a card in the
    /// level's colour: red, orange, blue, green.
    private static func triageCards(_ html: String) -> String {
        guard let section = html.range(of: "When to get help") ?? html.range(of: "When to see a doctor"),
              let tableStart = html.range(of: "<table", range: section.upperBound..<html.endIndex),
              let tableEnd = html.range(of: "</table>", range: tableStart.upperBound..<html.endIndex)
        else { return html }
        let table = String(html[tableStart.lowerBound..<tableEnd.upperBound])
        let cells = HTMLText.matches(#"<td[^>]*>(.*?)</td>"#, in: table).map { $0[0] }
        var cards: [String] = []
        var index = 0
        while index < cells.count {
            let heading = cells[index]
            // A heading cell has no list; the next cell is its list.
            guard !heading.contains("<li"), index + 1 < cells.count, cells[index + 1].contains("<li") else {
                index += 1
                continue
            }
            let title = HTMLText.plain(heading)
            let (level, symbol, color) = triageLevel(title)
            let icon = SymbolImage.tile(symbol, color: color)
            cards.append("""
                <div class="triage triage-\(level)">
                <div class="triage-title"><img class="hicon" src="\(icon)" alt="">\(title)</div>
                \(cells[index + 1])
                </div>
                """)
            index += 2
        }
        guard !cards.isEmpty else { return html }
        var html = html
        html.replaceSubrange(tableStart.lowerBound..<tableEnd.upperBound, with: cards.joined())
        return html
    }

    private static func triageLevel(_ title: String) -> (String, String, UIColor) {
        let text = title.lowercased()
        if text.contains("ambulance") || text.contains("000") { return ("red", "phone.fill", .systemRed) }
        if text.contains("hospital") || text.contains("emergency") { return ("orange", "cross.case.fill", .systemOrange) }
        if text.contains("doctor") || text.contains("gp") || text.contains("health professional") {
            return ("blue", "stethoscope", .systemBlue)
        }
        if text.contains("home") || text.contains("look after") { return ("green", "house.fill", .systemGreen) }
        return ("gray", "info.circle.fill", .systemGray)
    }

    /// Bold "call an ambulance (000)" lines, which the site shows in red:
    /// a whole paragraph becomes a red call-out card; in a list or a
    /// sentence, the words go red.
    private static func urgentWarnings(_ html: String) -> String {
        let phone = SymbolImage.tile("phone.fill", color: .systemRed)
        var html = replacing(#"<p[^>]*>\s*<(b|strong)>([^<]*(?:000|ambulance)[^<]*)</\1>\s*</p>"#, in: html) { groups in
            "<div class=\"urgent\"><img class=\"hicon\" src=\"\(phone)\" alt=\"\"><p>\(groups[2])</p></div>"
        }
        html = replacing(#"<(b|strong)>([^<]*(?:000|ambulance)[^<]*)</\1>"#, in: html) { groups in
            "<b class=\"urgent-text\">\(groups[2])</b>"
        }
        return html
    }

    /// An icon tile on each section heading, picked from its words.
    private static func sectionHeadings(_ html: String, accent: UIColor) -> String {
        replacing(#"<h2>(.*?)</h2>"#, in: html) { groups in
            let title = groups[1]
            let text = HTMLText.plain(title).lowercased()
            let (symbol, color) = headingStyle(text, accent: accent)
            let more = text.contains("more information") ? " class=\"more\"" : ""
            return "<h2\(more)><img class=\"hicon\" src=\"\(SymbolImage.tile(symbol, color: color))\" alt=\"\">\(title)</h2>"
        }
    }

    private static func headingStyle(_ text: String, accent: UIColor) -> (String, UIColor) {
        let rules: [(words: [String], symbol: String, color: UIColor)] = [
            (["when to get help", "when to see", "emergency", "warning"], "exclamationmark.triangle.fill", .systemRed),
            (["sign", "symptom"], "waveform.path.ecg", .systemPink),
            (["cause", "why"], "magnifyingglass", .systemIndigo),
            (["what is", "what are", "about", "overview"], "info.circle.fill", accent),
            (["care", "treat", "manag", "help your child", "at home", "what to do"], "heart.fill", .systemTeal),
            (["prevent", "avoid", "stop"], "shield.lefthalf.filled", .systemGreen),
            (["test", "diagnos", "scan"], "testtube.2", .systemBlue),
            (["medicine", "medication", "dose"], "pills.fill", .systemPurple),
            (["question"], "questionmark.bubble.fill", .systemOrange),
            (["more information", "resources", "further"], "book.fill", .systemBrown),
            (["after", "recovery", "follow"], "calendar", .systemCyan),
        ]
        if let rule = rules.first(where: { $0.words.contains(where: text.contains) }) {
            return (rule.symbol, rule.color)
        }
        return ("doc.text.fill", accent)
    }

    /// "Common questions" headings (h4) as question cards.
    private static func questions(_ html: String, accent: UIColor) -> String {
        let icon = SymbolImage.glyph("questionmark.circle.fill", color: .systemOrange)
        return replacing(#"<h4[^>]*>(.*?)</h4>"#, in: html) { groups in
            "<h4 class=\"question\"><img class=\"qicon\" src=\"\(icon)\" alt=\"\">\(groups[1])</h4>"
        }
    }

    // MARK: Helpers

    /// Removes the whole `<tag>` element that contains `position`, counting
    /// nested elements of the same tag to find its end.
    private static func removingElement(around position: String.Index, tag: String, in html: String) -> String {
        guard let range = elementRange(around: position, tag: tag, in: html) else { return html }
        var html = html
        html.removeSubrange(range)
        return html
    }

    /// Where the whole `<tag>` element containing `position` is, or nil if
    /// its end isn't in the text.
    private static func elementRange(around position: String.Index, tag: String, in html: String) -> Range<String.Index>? {
        guard let start = html.range(of: "<\(tag)", options: .backwards, range: html.startIndex..<position) else { return nil }
        var depth = 0
        var cursor = start.lowerBound
        while let next = html.range(of: "<\(tag)|</\(tag)>", options: .regularExpression, range: cursor..<html.endIndex) {
            depth += html[next].hasPrefix("</") ? -1 : 1
            cursor = next.upperBound
            if depth == 0 { return start.lowerBound..<next.upperBound }
        }
        return nil
    }

    /// Replaces each match of `pattern`; `groups[0]` is the whole match.
    private static func replacing(_ pattern: String, in text: String, with replacement: ([String]) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive])
        else { return text }
        var result = ""
        var last = text.startIndex
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text) else { continue }
            let groups = (0..<match.numberOfRanges).map { i in
                Range(match.range(at: i), in: text).map { String(text[$0]) } ?? ""
            }
            result += text[last..<range.lowerBound] + replacement(groups)
            last = range.upperBound
        }
        return result + text[last...]
    }

    // MARK: Page

    /// The whole page: pills (library, review date), the title, the "At a
    /// glance" button, the content and a short source line.
    /// The category a sheet's filed under on the site, with its icon.
    struct Category {
        var name: String
        var symbol: String
        var color: UIColor
    }

    static func page(title: String, library: FactSheet.Library, accent: UIColor, accentHex: String,
                     formatted: Result, category: Category?, offersGlance: Bool) -> String {
        // Under the title: what it's filed under, how long it takes to read,
        // and when it was last reviewed.
        let grey = UIColor.secondaryLabel.resolvedColor(with: .init(userInterfaceStyle: .light))
        var pills = ""
        if let category {
            let hex = category.color.hexString
            pills += "<span class=\"pill\" style=\"color: \(hex); background: color-mix(in srgb, \(hex) 14%, transparent)\">"
                + "<img src=\"\(SymbolImage.glyph(category.symbol, color: category.color))\" alt=\"\">\(escape(category.name))</span>"
        }
        // About 200 words a minute, for a parent reading carefully.
        let words = formatted.plainText.split(whereSeparator: \.isWhitespace).count
        let minutes = max(1, Int((Double(words) / 200).rounded()))
        pills += "<span class=\"pill muted\"><img src=\"\(SymbolImage.glyph("clock", color: grey))\" alt=\"\">\(minutes) min read</span>"
        if let reviewed = formatted.reviewed {
            pills += "<span class=\"pill muted\"><img src=\"\(SymbolImage.glyph("calendar", color: grey))\" alt=\"\">Reviewed \(escape(reviewed))</span>"
        }
        let glance = offersGlance ? """
            <a class="glance" href="\(FactSheetGlance.linkURL.absoluteString)">
            <img class="hicon" src="\(SymbolImage.tile("sparkles", color: accent))" alt="">
            <span><b>At a glance</b><small>A short summary and the key things to know</small></span>
            <img class="chevron" src="\(SymbolImage.glyph("chevron.right", color: .systemGray2, size: 14))" alt="">
            </a>
            """ : ""
        return """
        <!doctype html><html><head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>\(css(accentHex: accentHex))</style></head><body>
        <header>
        <h1 class="title">\(escape(title))</h1>
        <div class="pills">\(pills)</div>
        \(glance)
        </header>
        <article>\(formatted.html)</article>
        <p class="source">From The Royal Children’s Hospital \(escape(library.title)). For advice about your child, talk to their doctor or care team.</p>
        </body></html>
        """
    }

    private static func css(accentHex: String) -> String {
        """
        :root { color-scheme: light dark; --accent: \(accentHex); --brand: #219EBD;
                --card: rgba(120,120,128,0.10); --text2: rgba(60,60,67,0.75); }
        @media (prefers-color-scheme: dark) { :root { --brand: #62C7E0; --text2: rgba(235,235,245,0.65); } }
        /* A normal page: nothing wider than the screen, no sideways scrolling. */
        html, body { overflow-x: hidden; max-width: 100%; }
        body { font: -apple-system-body; font-family: -apple-system, sans-serif; line-height: 1.55;
               margin: 0; padding: 8px 20px 40px; -webkit-text-size-adjust: 100%;
               overflow-wrap: break-word; touch-action: pan-y; }
        article * { max-width: 100%; box-sizing: border-box; }
        /* The site's page builder wraps everything in a one-item list. */
        ul[role="presentation"] { list-style: none; padding: 0; margin: 0; }
        li[role="presentation"] { margin: 0; }
        li[role="presentation"]::marker { content: ""; }
        a { color: var(--brand); }
        .pills { display: flex; flex-wrap: wrap; gap: 8px; margin: 0 0 16px; }
        .pill { display: inline-flex; align-items: center; gap: 6px; font-size: 0.8em; font-weight: 600;
                padding: 5px 11px; border-radius: 999px; color: var(--accent);
                background: color-mix(in srgb, var(--accent) 14%, transparent); }
        .pill.muted { color: var(--text2); background: var(--card); }
        .pill img { width: 14px; height: 14px; }
        h1.title { font-size: 1.9em; line-height: 1.15; margin: 8px 0 12px; letter-spacing: -0.01em; }
        .glance { display: flex; align-items: center; gap: 12px; text-decoration: none; color: inherit;
                  padding: 14px 16px; border-radius: 18px; margin-bottom: 8px;
                  background: color-mix(in srgb, var(--accent) 10%, transparent); }
        .glance span { flex: 1; display: flex; flex-direction: column; }
        .glance small { color: var(--text2); font-size: 0.85em; }
        .glance .chevron { width: 12px; height: 12px; }
        .hicon { width: 30px; height: 30px; border-radius: 8px; flex: none; }
        h2 { display: flex; align-items: center; gap: 12px; font-size: 1.25em; line-height: 1.25;
             margin: 1.8em 0 0.6em; }
        h3 { font-size: 1.05em; margin: 1.4em 0 0.4em; padding-left: 10px;
             border-left: 3px solid color-mix(in srgb, var(--accent) 60%, transparent); }
        p { margin: 0.6em 0; }
        ul, ol { padding-left: 1.3em; margin: 0.5em 0; }
        li { margin: 0.35em 0; }
        li::marker { color: var(--accent); }
        img { max-width: 100%; height: auto; }
        p img, article > img { border-radius: 14px; }
        /* Figure captions: small and grey, however the site marks them. */
        .caption, figcaption, p:has(> img) + p, p:has(> img) + p * {
            color: var(--text2); font-size: 0.8em; line-height: 1.4; font-weight: normal; }
        .caption, p:has(> img) + p { margin-top: -0.2em; }
        .keypoints { border-radius: 20px; padding: 4px 18px 10px; margin: 8px 0 4px;
                     background: color-mix(in srgb, var(--accent) 10%, transparent); }
        .keypoints h2 { margin-top: 14px; }
        .keypoints ul { list-style: none; padding-left: 0; }
        .keypoints li { position: relative; padding-left: 28px; }
        .keypoints li::before { content: "✓"; position: absolute; left: 0; top: 0; font-weight: 700;
                                color: var(--accent); width: 20px; text-align: center; }
        .urgent { display: flex; gap: 12px; align-items: flex-start; border-radius: 16px;
                  padding: 12px 14px; margin: 12px 0; background: rgba(255,59,48,0.12); }
        .urgent p { margin: 2px 0; font-weight: 600; color: #D70015; }
        .urgent-text { color: #D70015; }
        @media (prefers-color-scheme: dark) { .urgent p, .urgent-text { color: #FF6961; } .urgent { background: rgba(255,69,58,0.18); } }
        .triage { border-radius: 16px; padding: 12px 16px 6px; margin: 10px 0; }
        .triage-title { display: flex; align-items: center; gap: 10px; font-weight: 700; }
        .triage .hicon { width: 26px; height: 26px; border-radius: 7px; }
        .triage p { margin: 0; }
        .triage-red { background: rgba(255,59,48,0.10); }
        .triage-orange { background: rgba(255,149,0,0.12); }
        .triage-blue { background: rgba(0,122,255,0.10); }
        .triage-green { background: rgba(52,199,89,0.12); }
        .triage-gray { background: var(--card); }
        h4.question { display: flex; gap: 10px; align-items: flex-start; font-size: 1em; margin: 1.2em 0 0.3em; }
        .qicon { width: 20px; height: 20px; flex: none; margin-top: 2px; }
        h4.question + p { margin-top: 0.2em; }
        h2.more + ul { list-style: none; padding: 6px 16px; border-radius: 16px; background: var(--card); }
        h2.more + ul li { padding: 6px 0; border-bottom: 0.5px solid rgba(128,128,128,0.25); }
        h2.more + ul li:last-child { border-bottom: none; }
        table { border-collapse: collapse; width: 100%; display: block; overflow-x: auto; }
        th, td { border: 1px solid rgba(128,128,128,0.3); padding: 6px 8px; text-align: left; vertical-align: top; }
        .source { color: var(--text2); font-size: 0.85em; margin-top: 2.4em; padding-top: 1em;
                  border-top: 0.5px solid rgba(128,128,128,0.3); }
        """
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

nonisolated extension UIColor {
    /// e.g. "#34C759", for CSS.
    var hexString: String {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func byte(_ value: CGFloat) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
    }
}

// MARK: - Icons

/// SF Symbols drawn as images for the web page, which can't use them
/// directly: a white symbol on a coloured rounded tile, or a coloured
/// symbol on its own. As data URIs, so they work offline.
nonisolated enum SymbolImage {
    static func tile(_ name: String, color: UIColor, size: CGFloat = 30) -> String {
        render(size: CGSize(width: size, height: size)) { rect in
            color.setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: size * 0.27).fill()
            draw(name, color: .white, pointSize: size * 0.5, in: rect)
        }
    }

    static func glyph(_ name: String, color: UIColor, size: CGFloat = 20) -> String {
        render(size: CGSize(width: size, height: size)) { rect in
            draw(name, color: color, pointSize: size * 0.85, in: rect)
        }
    }

    private static func draw(_ name: String, color: UIColor, pointSize: CGFloat, in rect: CGRect) {
        let configuration = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        guard let symbol = UIImage(systemName: name, withConfiguration: configuration)?
            .withTintColor(color, renderingMode: .alwaysOriginal) else { return }
        // Fitted and centred, keeping the symbol's shape.
        let scale = min(rect.width * 0.8 / symbol.size.width, rect.height * 0.8 / symbol.size.height, 1)
        let size = CGSize(width: symbol.size.width * scale, height: symbol.size.height * scale)
        symbol.draw(in: CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2,
                               width: size.width, height: size.height))
    }

    private static func render(size: CGSize, _ drawing: (CGRect) -> Void) -> String {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            drawing(CGRect(origin: .zero, size: size))
        }
        return "data:image/png;base64," + (image.pngData()?.base64EncodedString() ?? "")
    }
}

// MARK: - At a glance

/// An on-device summary of a fact sheet: in short, the key things to know,
/// and when to get help, taken only from the page.
enum FactSheetGlance {
    /// The page's "At a glance" button links here; the reader opens the
    /// summary instead of following it.
    nonisolated static let linkURL = URL(string: "myrch-glance://summary")!

    static let instructions = """
        You are summarising a Royal Children's Hospital fact sheet for a \
        parent. Use only what the fact sheet says; don't add advice, \
        doses or details it doesn't contain. Keep any instruction to call \
        an ambulance (000) or go to hospital exactly as the fact sheet \
        says it.
        """

    /// The fact sheet, cut to fit the model's context window.
    private static let textLimit = 6_000

    static func brief(for sheet: FactSheet, text: String) -> AIBrief {
        let context = "Fact sheet: \(sheet.title) (\(sheet.library.title))\n\nFact sheet text:\n"
            + OnDeviceAI.clip(text, to: textLimit)
        return AIBrief(context: context, sections: [
            AISection(title: "In short", systemImage: "text.alignleft",
                      request: "In two or three short sentences, summarise what this fact sheet is about and the most important message for a parent. Reply with only the summary."),
            AISection(title: "Key things to know", systemImage: "checklist",
                      request: "Now list the three to five most important things a parent should know from this fact sheet, one per line starting with \"- \". Keep each to one short sentence. Reply with only the list."),
            AISection(title: "When to get help", systemImage: "exclamationmark.triangle.fill",
                      request: "Now list the warning signs the fact sheet says need urgent help or a doctor, one per line starting with \"- \", keeping any instruction to call 000 as the fact sheet says it. If it lists none, say so in one sentence. Reply with only the list."),
        ])
    }
}

/// The summary sheet for a fact sheet.
struct FactSheetGlanceSheet: View {
    let sheet: FactSheet
    let text: String

    var body: some View {
        AIExplainSheet(heading: sheet.title, navigationTitle: "At a Glance",
                       instructions: FactSheetGlance.instructions) {
            FactSheetGlance.brief(for: sheet, text: text)
        }
    }
}
