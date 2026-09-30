import SwiftUI

/// Something the app is built on or includes, with the terms it's used under.
struct LicenceEntry: Identifiable {
    let name: String
    let summary: String
    let text: String
    var id: String { name }

    /// myRCH has no third-party packages, so this is the app's own licence
    /// plus the sources it credits. Add an entry for any package added later.
    static let all: [LicenceEntry] = [myRCH, whoGrowthStandards, apple]

    static let myRCH = LicenceEntry(
        name: "myRCH",
        summary: "MIT License",
        text: """
        MIT License

        Copyright (c) 2026 glowbase

        Permission is hereby granted, free of charge, to any person obtaining a copy \
        of this software and associated documentation files (the "Software"), to deal \
        in the Software without restriction, including without limitation the rights \
        to use, copy, modify, merge, publish, distribute, sublicense, and/or sell \
        copies of the Software, and to permit persons to whom the Software is \
        furnished to do so, subject to the following conditions:

        The above copyright notice and this permission notice shall be included in all \
        copies or substantial portions of the Software.

        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR \
        IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, \
        FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE \
        AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER \
        LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, \
        OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE \
        SOFTWARE.
        """)

    static let whoGrowthStandards = LicenceEntry(
        name: "WHO Child Growth Standards",
        summary: "World Health Organization",
        text: """
        The growth charts' percentile curves are modelled on the WHO Child Growth \
        Standards, published by the World Health Organization.

        The curves in this version of myRCH are approximate values for showing how \
        a child is growing. They are not the official WHO tables and aren't for \
        clinical use. Ask your child's care team about their growth.

        WHO Multicentre Growth Reference Study Group. WHO Child Growth Standards: \
        Length/height-for-age, weight-for-age, weight-for-length, weight-for-height \
        and body mass index-for-age: Methods and development. Geneva: World Health \
        Organization, 2006.
        """)

    static let apple = LicenceEntry(
        name: "Apple Frameworks and SF Symbols",
        summary: "Apple Inc.",
        text: """
        myRCH is built with Apple's SDKs, including SwiftUI, Swift Charts, WidgetKit \
        and PDFKit, and uses SF Symbols for its icons. They are used under the Apple \
        Developer Program License Agreement.

        SF Symbols are provided by Apple Inc. and may not be used outside apps for \
        Apple platforms.
        """)
}

/// Settings > Licences: the app's own licence and what it credits.
struct LicencesView: View {
    var body: some View {
        List {
            Section {
                ForEach(LicenceEntry.all) { entry in
                    NavigationLink {
                        LicenceDetailView(entry: entry)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.name)
                            Text(entry.summary)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } footer: {
                Text("myRCH doesn't include any third-party code.")
            }
        }
        .navigationTitle("Licences")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct LicenceDetailView: View {
    let entry: LicenceEntry

    var body: some View {
        ScrollView {
            Text(entry.text)
                .font(.footnote.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(entry.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { LicencesView() }
}
