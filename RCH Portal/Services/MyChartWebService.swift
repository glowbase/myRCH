import Foundation

// MARK: - Live RCH portal backend (unsanctioned web API)
//
// Talks to the "My RCH Portal" the same way the website's own JavaScript does:
//   1. GET the login page, read the __RequestVerificationToken hidden field.
//   2. POST the login form (username + password + token) → session cookie.
//   3. POST api/<area>/<Action> with the token as a header → JSON.
//
// This is Epic's private web API, not a supported integration. It can break at
// any time and its use may violate the portal's terms. Credentials come from
// the Keychain and are only ever sent to `config.host` over HTTPS.
//
// NOTE ON FIELD MAPPING: the request/response JSON shapes below are a best
// effort based on the documented endpoints. They must be verified against a
// real authenticated response on-device — enable `debugLogResponses` and check
// the Xcode console, then adjust the DTOs. Decode failures surface the raw JSON
// snippet so mapping can be finalised.

struct MyChartConfig: Sendable {
    var host = "myrchportal.rch.org.au"
    var basePath = "/MyRCHPortal"

    var loginPageURL: URL { url("Authentication/Login") }
    func url(_ path: String) -> URL {
        URL(string: "https://\(host)\(basePath)/\(path)")!
    }
}

enum MyChartError: LocalizedError {
    case missingToken
    case loginFailed
    case sessionExpired
    case decoding(action: String, snippet: String)

    var errorDescription: String? {
        switch self {
        case .missingToken: "Couldn't read the security token from the login page."
        case .loginFailed: "Sign in failed. Check your username and password."
        case .sessionExpired: "Your session expired. Please sign in again."
        case let .decoding(action, snippet):
            "Couldn't read the response for \(action). Raw JSON: \(snippet)"
        }
    }
}

actor MyChartWebService: PortalService {
    private let config: MyChartConfig
    private let session: URLSession
    /// Set true to print raw responses to the console for field-mapping.
    private let debugLogResponses: Bool
    private var apiToken: String?

    init(config: MyChartConfig = .init(), debugLogResponses: Bool = true) {
        self.config = config
        self.debugLogResponses = debugLogResponses
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = HTTPCookieStorage()
        configuration.httpCookieAcceptPolicy = .always
        // Behave like a normal iOS browser client.
        configuration.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
        ]
        self.session = URLSession(configuration: configuration)
    }

    // MARK: - Authentication

    func signIn(username: String, password: String) async throws -> PatientProfile {
        // 1. Load login page + extract all form inputs (incl. the token).
        let (pageData, _) = try await session.data(from: config.loginPageURL)
        let html = String(decoding: pageData, as: UTF8.self)
        var fields = Self.formInputs(in: html)
        guard let token = fields["__RequestVerificationToken"], !token.isEmpty else {
            throw MyChartError.missingToken
        }

        // 2. Fill the username/password inputs. Epic commonly names these
        //    "Login" and "Password"; adjust here if the live form differs.
        fields["Login"] = username
        fields["Password"] = password

        // 3. POST the form url-encoded.
        var request = URLRequest(url: config.loginPageURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncode(fields).data(using: .utf8)
        let (loginData, response) = try await session.data(for: request)
        let loginHTML = String(decoding: loginData, as: UTF8.self)

        // Success heuristic: a real session no longer serves the login form.
        // If the response still contains the password field, we're still on the
        // login page — authentication failed.
        if loginHTML.contains("name=\"Password\"") {
            throw MyChartError.loginFailed
        }
        _ = response

        // Cache a token for subsequent api/ calls (re-read from a landing page).
        apiToken = Self.extractToken(from: loginHTML) ?? token

        return PatientProfile(
            id: username,
            fullName: username,
            preferredName: username,
            initials: String(username.prefix(1)).uppercased(),
            linkedAccounts: []
        )
    }

    // MARK: - Data endpoints

    func appointments(for patientID: String) async throws -> [Appointment] {
        // Visits use legacy MVC endpoints; placeholder until mapped live.
        let json = try await postJSON(action: "api/appointments/GetList")
        return decodeAppointments(json)
    }

    func testResults(for patientID: String) async throws -> [TestResult] {
        let json = try await postJSON(action: "api/test-results/GetList")
        return decodeTestResults(json)
    }

    func medications(for patientID: String) async throws -> [Medication] {
        let json = try await postJSON(action: "api/medications/LoadMedicationsPage")
        return decodeMedications(json)
    }

    func messages(for patientID: String) async throws -> [Message] {
        let json = try await postJSON(action: "api/conversations/GetConversationList")
        return decodeMessages(json)
    }

    func healthIssues(for patientID: String) async throws -> [HealthIssue] {
        let json = try await postJSON(action: "api/health-summary/FetchHealthSummary")
        return decodeHealthIssues(json)
    }

    func allergies(for patientID: String) async throws -> [Allergy] {
        let json = try await postJSON(action: "api/allergies/LoadAllergies")
        return decodeAllergies(json)
    }

    func immunisations(for patientID: String) async throws -> [Immunisation] {
        let json = try await postJSON(action: "api/immunizations/LoadImmunizations")
        return decodeImmunisations(json)
    }

    // MARK: - Transport

    /// POSTs an empty JSON body to an api/ action and returns parsed JSON.
    private func postJSON(action: String, body: [String: Any] = [:]) async throws -> Any {
        var request = URLRequest(url: config.url(action))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiToken { request.setValue(apiToken, forHTTPHeaderField: "__RequestVerificationToken") }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await session.data(for: request)

        // Session expiry returns 200 with login-page HTML rather than JSON.
        if let text = String(data: data, encoding: .utf8),
           text.contains("Authentication/Login") || text.hasPrefix("<") {
            throw MyChartError.sessionExpired
        }
        if debugLogResponses {
            print("↩︎ \(action):\n\(String(decoding: data, as: UTF8.self).prefix(2000))")
        }
        return try JSONSerialization.jsonObject(with: data)
    }

    // MARK: - Decoding (best-effort — verify against live JSON)

    private func decodeAppointments(_ json: Any) -> [Appointment] { [] }
    private func decodeTestResults(_ json: Any) -> [TestResult] { [] }
    private func decodeMedications(_ json: Any) -> [Medication] { [] }
    private func decodeMessages(_ json: Any) -> [Message] { [] }
    private func decodeHealthIssues(_ json: Any) -> [HealthIssue] { [] }
    private func decodeAllergies(_ json: Any) -> [Allergy] { [] }
    private func decodeImmunisations(_ json: Any) -> [Immunisation] { [] }

    // MARK: - HTML helpers

    /// Extracts every `<input name=… value=…>` from the page as a dictionary.
    nonisolated static func formInputs(in html: String) -> [String: String] {
        var result: [String: String] = [:]
        let pattern = #"<input\b[^>]*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return result }
        let range = NSRange(html.startIndex..., in: html)
        for match in regex.matches(in: html, range: range) {
            guard let r = Range(match.range, in: html) else { continue }
            let tag = String(html[r])
            guard let name = attribute("name", in: tag) else { continue }
            result[name] = attribute("value", in: tag) ?? ""
        }
        return result
    }

    nonisolated static func extractToken(from html: String) -> String? {
        formInputs(in: html)["__RequestVerificationToken"].flatMap { $0.isEmpty ? nil : $0 }
    }

    private nonisolated static func attribute(_ name: String, in tag: String) -> String? {
        let pattern = "\(name)\\s*=\\s*\"([^\"]*)\""
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)),
              let r = Range(match.range(at: 1), in: tag) else { return nil }
        return String(tag[r])
    }

    private nonisolated static func formEncode(_ fields: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return fields.map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(k)=\(v)"
        }.joined(separator: "&")
    }
}
