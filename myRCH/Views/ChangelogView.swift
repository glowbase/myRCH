import SwiftUI

/// One release from CHANGELOG.md.
struct ChangelogRelease: Identifiable, Equatable {
    struct Group: Identifiable, Equatable {
        /// The `###` heading, or "" for items listed straight under the release.
        var title: String
        var items: [String]

        var id: String { title }
    }

    var version: String
    /// As written in the file, e.g. "2026-10-04".
    var date: String
    var groups: [Group]

    var id: String { version }

    /// Reads the bundled CHANGELOG.md, newest release first. Skips the
    /// introduction and any release with nothing listed yet (such as an
    /// empty Unreleased).
    static func bundled() -> [ChangelogRelease] {
        guard let url = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return parse(text)
    }

    /// Understands just the Keep a Changelog subset the file uses:
    /// `## [version] - date`, `### Group` and `- item` lines.
    static func parse(_ text: String) -> [ChangelogRelease] {
        var releases: [ChangelogRelease] = []
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("## ") {
                let heading = line.dropFirst(3)
                let parts = heading.components(separatedBy: " - ")
                let version = parts[0].trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
                let date = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
                releases.append(ChangelogRelease(version: version, date: date, groups: []))
            } else if line.hasPrefix("### "), !releases.isEmpty {
                releases[releases.count - 1].groups.append(Group(title: String(line.dropFirst(4)), items: []))
            } else if line.hasPrefix("- "), !releases.isEmpty {
                if releases[releases.count - 1].groups.isEmpty {
                    releases[releases.count - 1].groups.append(Group(title: "", items: []))
                }
                let last = releases[releases.count - 1].groups.count - 1
                releases[releases.count - 1].groups[last].items.append(String(line.dropFirst(2)))
            }
        }
        return releases.filter { release in release.groups.contains { !$0.items.isEmpty } }
    }
}

/// Settings > Version: what's changed in each release.
struct ChangelogView: View {
    private let releases = ChangelogRelease.bundled()

    var body: some View {
        List {
            ForEach(releases) { release in
                Section {
                    ForEach(release.groups) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            if !group.title.isEmpty {
                                Text(group.title)
                                    .font(.subheadline.weight(.semibold))
                            }
                            ForEach(group.items, id: \.self) { item in
                                Label {
                                    Text(markdown(item))
                                } icon: {
                                    Image(systemName: "circle.fill")
                                        .font(.system(size: 5))
                                        .foregroundStyle(.secondary)
                                }
                                .font(.subheadline)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text(heading(for: release))
                }
            }
        }
        .overlay {
            if releases.isEmpty {
                ContentUnavailableView("No Changes Listed", systemImage: "list.bullet.rectangle")
            }
        }
        .navigationTitle("What's New")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func heading(for release: ChangelogRelease) -> String {
        let date = (try? Date(release.date, strategy: .iso8601.year().month().day()))
            .map { $0.formatted(date: .long, time: .omitted) }
        return [release.version == "Unreleased" ? "Coming Next" : "Version \(release.version)", date]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    /// Bold and links in an item, falling back to the plain text.
    private func markdown(_ item: String) -> AttributedString {
        (try? AttributedString(markdown: item)) ?? AttributedString(item)
    }
}

#Preview {
    NavigationStack { ChangelogView() }
}
