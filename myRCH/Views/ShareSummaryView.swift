import SwiftUI

/// Share My Record: a one-page PDF health summary to hand to a GP, school,
/// carer or another hospital. Built on the device from the portal data;
/// you choose what goes in, and nothing is sent until you share it.
struct ShareSummaryView: View {
    let patientID: String
    @Environment(Session.self) private var session

    @State private var header: RecordHeader?
    @State private var allergies: [Allergy] = []
    /// False when they couldn't be read: the PDF says so, never "none".
    @State private var allergiesKnown = false
    @State private var conditions: [HealthIssue] = []
    @State private var medications: [Medication] = []
    @State private var immunisations: [ImmunisationGroup] = []
    @State private var isLoading = true

    @State private var includesUR = true
    @State private var includesAllergies = true
    @State private var includesConditions = true
    @State private var includesMedication = true
    @State private var includesImmunisations = false
    @State private var pdf: URL?
    /// An optional plain-language paragraph at the top, drafted on device
    /// and edited by the family before sharing.
    @State private var includesIntro = false
    @State private var intro = ""
    @State private var isWritingIntro = false
    @State private var introFailure: String?

    private var name: String { header?.fullName ?? session.activeAccount?.name ?? "Patient" }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "person.2.wave.2.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Feature.sharing.tileArt.color, Feature.sharing.tileArt.color.lighter)
                        .font(.system(size: 40))
                    Text("Share a Health Summary")
                        .font(.system(.title2, design: .rounded).bold())
                    Text("Make a PDF of \(session.activeAccount?.name ?? "your child")'s key health details to give to a GP, school, carer or another hospital.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }

            Section {
                Toggle("UR number and date of birth", isOn: $includesUR)
                Toggle(allergiesKnown ? "Allergies (\(allergies.count))" : "Allergies (not available)",
                       isOn: $includesAllergies)
                Toggle("Conditions (\(conditions.count))", isOn: $includesConditions)
                Toggle("Current medication (\(medications.count))", isOn: $includesMedication)
                Toggle("Immunisations (\(immunisations.count))", isOn: $includesImmunisations)
            } header: {
                Text("Include")
            } footer: {
                Text("Only what's switched on goes in the PDF. Nothing is sent until you choose where to share it.")
            }
            .disabled(isLoading)

            if OnDeviceAI.isSupported { introSection }

            Section {
                if let pdf {
                    ShareLink(item: pdf) {
                        Label("Share Summary", systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(isLoading ? "Loading the record…" : "Preparing the PDF…")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Share My Record")
        .navigationBarTitleDisplayMode(.inline)
        .tint(Theme.brand)
        .task(id: patientID) { await load() }
        .task(id: selection) {
            guard !isLoading else { return }
            // Waits out typing in the summary before re-rendering.
            if includesIntro { try? await Task.sleep(for: .milliseconds(400)) }
            guard !Task.isCancelled else { return }
            pdf = DocumentPDF.write(html: html, named: "Health Summary – \(name)")
        }
    }

    private struct Selection: Hashable {
        var flags: [Bool]
        var intro: String
    }

    /// Changes whenever the PDF needs rebuilding.
    private var selection: Selection {
        Selection(flags: [isLoading, includesUR, includesAllergies, includesConditions, includesMedication,
                          includesImmunisations, includesIntro],
                  intro: intro)
    }

    // MARK: Summary paragraph

    private var introSection: some View {
        Section {
            Toggle("Add a short summary", isOn: $includesIntro)
                .disabled(isLoading)
                .onChange(of: includesIntro) {
                    if includesIntro, intro.isEmpty { Task { await writeIntro() } }
                }
            if includesIntro {
                if isWritingIntro {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Writing a summary…").foregroundStyle(.secondary)
                    }
                } else {
                    TextField("A few sentences about your child's health", text: $intro, axis: .vertical)
                        .lineLimit(3...10)
                    Button("Rewrite", systemImage: "sparkles") { Task { await writeIntro() } }
                }
                if let introFailure {
                    Label(introFailure, systemImage: "exclamationmark.bubble")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        } footer: {
            Text("A plain-language paragraph at the top, for a teacher, carer or GP. Apple Intelligence drafts it on this iPhone from what's switched on above; check and edit it before sharing.")
        }
    }

    private func writeIntro() async {
        if let reason = OnDeviceAI.unavailableReason {
            introFailure = reason
            return
        }
        isWritingIntro = true
        introFailure = nil
        defer { isWritingIntro = false }
        do {
            intro = try await OnDeviceAI.respond(instructions: Self.introInstructions, prompt: introPrompt)
        } catch {
            OnDeviceAI.logFailure("Share summary intro", error)
            introFailure = "Couldn't write a summary. You can type your own."
        }
    }

    private static let introInstructions = """
        You are writing the opening paragraph of a child's health summary, \
        which the parent will give to a teacher, carer or GP. In three or \
        four sentences, introduce the child's main health needs in plain \
        words, based only on the details given, in the third person using \
        the child's first name. Mention allergies that matter for day-to-day \
        care. Don't give instructions or advice, and don't add anything \
        that isn't listed.
        """

    /// What's switched on, so the paragraph matches the PDF.
    private var introPrompt: String {
        var lines = ["Child's first name: \(name.split(separator: " ").first.map(String.init) ?? name)"]
        if let birth = session.activeAccount?.dateOfBirth { lines.append("Age: \(birth.ageDescription)") }
        if includesConditions {
            lines += RecordContext.block("Conditions", conditions.map { "- \($0.name)" })
        }
        // Unknown allergies are left out, so the paragraph can't call them none.
        if includesAllergies, allergiesKnown {
            lines += RecordContext.block("Allergies", allergies.map { allergy in
                let detail = [allergy.reaction, allergy.severity].filter { !$0.isEmpty }.joined(separator: ", ")
                return "- \(allergy.substance)" + (detail.isEmpty ? "" : " (\(detail))")
            })
        }
        if includesMedication {
            lines += RecordContext.block("Current medicines", medications.map { "- \($0.reminderName)" })
        }
        lines.append("")
        lines.append("Write the opening paragraph. Reply with only the paragraph.")
        return lines.joined(separator: "\n")
    }

    private func load() async {
        let service = session.service
        async let headerTask = try? service.recordHeader(for: patientID)
        async let allergiesTask = try? service.allergies(for: patientID)
        async let issuesTask = try? service.healthIssues(for: patientID)
        async let medicationsTask = try? service.medications(for: patientID)
        async let immunisationsTask = try? service.immunisations(for: patientID)
        header = await headerTask
        // Still fetched when unreadable, so the response's shape is logged.
        let loadedAllergies = await allergiesTask
        allergiesKnown = service.readsAllergies && loadedAllergies != nil
        allergies = allergiesKnown ? (loadedAllergies ?? []) : []
        conditions = await issuesTask ?? []
        medications = (await medicationsTask ?? []).filter(\.isActive)
        immunisations = ImmunisationGroup.group(await immunisationsTask ?? [])
        isLoading = false
    }

    // MARK: PDF content

    private nonisolated static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private func section(_ title: String, empty: String, rows: [String]) -> String {
        let body = rows.isEmpty ? "<p class=\"empty\">\(empty)</p>"
                                : "<ul>" + rows.map { "<li>\($0)</li>" }.joined() + "</ul>"
        return "<h2>\(title)</h2>\(body)"
    }

    private var html: String {
        let e = Self.escape
        var parts: [String] = []
        var facts: [String] = []
        if includesUR {
            if let ur = header?.urNumber { facts.append("UR \(e(ur))") }
            if let birth = session.activeAccount?.dateOfBirth {
                facts.append("Born \(birth.formatted(date: .long, time: .omitted)) (\(birth.ageDescription))")
            }
        }
        parts.append("<h1>\(e(name))</h1>")
        if !facts.isEmpty { parts.append("<p class=\"facts\">\(facts.joined(separator: " · "))</p>") }
        let introText = intro.trimmingCharacters(in: .whitespacesAndNewlines)
        if includesIntro, !introText.isEmpty {
            parts.append("<p class=\"intro\">\(e(introText).replacingOccurrences(of: "\n", with: "<br>"))</p>")
        }

        if includesAllergies {
            parts.append(section("Allergies",
                                 empty: allergiesKnown ? "No known allergies recorded."
                                     : AllergyNotice.text(readsAllergies: session.service.readsAllergies),
                                 rows: allergies.map { allergy in
                let detail = [allergy.reaction, allergy.severity].filter { !$0.isEmpty }.map(e).joined(separator: ", ")
                return "<b>\(e(allergy.substance))</b>" + (detail.isEmpty ? "" : " – \(detail)")
            }))
        }
        if includesConditions {
            parts.append(section("Conditions", empty: "None recorded.", rows: conditions.map { e($0.name) }))
        }
        if includesMedication {
            parts.append(section("Current medication", empty: "None recorded.", rows: medications.map { medication in
                let detail = [medication.dose, medication.instructions].filter { !$0.isEmpty }.map(e).joined(separator: ". ")
                return "<b>\(e(medication.name))</b>" + (detail.isEmpty ? "" : "<br><span class=\"sub\">\(detail)</span>")
            }))
        }
        if includesImmunisations {
            parts.append(section("Immunisations", empty: "None on file.", rows: immunisations.map { group in
                "\(e(group.name)) – " + group.dates.map(\.mediumDate).joined(separator: ", ")
            }))
        }
        parts.append("<p class=\"footer\">Made with myRCH on \(Date.now.formatted(date: .long, time: .shortened)) from My RCH Portal records. Check with the treating team before relying on it. myRCH isn't made or endorsed by The Royal Children's Hospital.</p>")

        return """
        <!DOCTYPE html><html><head><meta charset="utf-8"><style>
        body { font-family: -apple-system, Helvetica, sans-serif; font-size: 11pt; color: #1c1c1e; }
        h1 { font-size: 22pt; margin: 0 0 4pt; }
        h2 { font-size: 13pt; color: #0f7690; border-bottom: 1px solid #d1d1d6; padding-bottom: 3pt; margin-top: 16pt; }
        .facts { color: #3a3a3c; margin: 0; }
        .intro { margin: 12pt 0 0; line-height: 1.4; }
        ul { padding-left: 16pt; margin: 6pt 0; } li { margin-bottom: 4pt; }
        .sub { color: #636366; font-size: 10pt; } .empty { color: #636366; }
        .footer { margin-top: 24pt; font-size: 8.5pt; color: #8e8e93; }
        </style></head><body>\(parts.joined())</body></html>
        """
    }
}
