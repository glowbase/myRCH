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

nonisolated struct MyChartConfig: Sendable {
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
    case twoFactorRequired
    case portalError(code: String?)
    case codeSendFailed
    case invalidCode(expired: Bool)
    case sessionExpired
    case decoding(action: String, snippet: String)
    /// An action like Bookmark came back without `isSuccess`.
    case actionFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingToken: "Couldn't read the security token from the login page."
        case .loginFailed: "Sign in failed. Check your username and password."
        case .twoFactorRequired: "Enter the verification code to finish signing in."
        case .codeSendFailed: "We couldn't send a verification code. Please try again."
        case let .invalidCode(expired):
            expired ? "That code has expired. Request a new one and try again."
                    : "That code isn't right. Check it and try again."
        case let .portalError(code): "The portal rejected the sign-in (error \(code ?? "unknown"))."
        case .sessionExpired: "Your session expired. Please sign in again."
        case let .actionFailed(action): "The portal couldn't complete that (\(action)). Please try again."
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
    /// Username from the in-progress sign-in, used to build the profile.
    private var pendingUsername: String?
    /// Set while the portal is waiting for a verification code.
    private var twoFactor: TwoFactorContext?

    init(config: MyChartConfig = .init(), debugLogResponses: Bool = true) {
        self.config = config
        self.debugLogResponses = debugLogResponses
        // Ephemeral gives a private, in-memory cookie jar that URLSession
        // reliably round-trips (a hand-made HTTPCookieStorage() may not), and
        // keeps health data out of the on-disk URL cache.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .always
        // Behave like a normal iOS browser client.
        configuration.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
        ]
        self.session = URLSession(configuration: configuration)
    }

    // MARK: - Authentication

    func signIn(username: String, password: String) async throws -> PatientProfile {
        // 1. Load the login page. The visible form posts nowhere (action="#");
        //    the page's loginpagecontroller.js instead submits the hidden
        //    `actualLogin` form to Authentication/Login/DoLogin, so read the
        //    hidden fields (token + navigation metrics) from that form only.
        let (pageData, _) = try await session.data(from: config.loginPageURL)
        let html = String(decoding: pageData, as: UTF8.self)
        var fields = Self.formInputs(in: html, containerID: "actualLogin")
        guard let token = fields["__RequestVerificationToken"], !token.isEmpty else {
            throw MyChartError.missingToken
        }

        // 2. Mirror `_submitLogin`: credentials go in a `LoginInfo` JSON field,
        //    each value base64-encoded from UTF-8 (WP.Utils.b64EncodeUnicode).
        let loginInfo: [String: Any] = [
            "Type": "StandardLogin",
            "Credentials": [
                "LoginIdentifier": Data(username.utf8).base64EncodedString(),
                "Password": Data(password.utf8).base64EncodedString()
            ]
        ]
        let loginJSON = try JSONSerialization.data(withJSONObject: loginInfo)
        fields["LoginInfo"] = String(decoding: loginJSON, as: UTF8.self)
        if let deviceID = Keychain.deviceID { fields["DeviceId"] = deviceID }
        if debugLogResponses {
            // Names only — the anti-forgery cookie must be present for DoLogin.
            let names = session.configuration.httpCookieStorage?.cookies(for: config.loginPageURL)?.map(\.name) ?? []
            print("↩︎ Cookies before DoLogin: \(names.sorted())")
        }

        // 3. POST the form url-encoded. URLSession follows the redirect, so the
        //    final URL tells us where the portal sent us.
        var request = URLRequest(url: config.url("Authentication/Login/DoLogin"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("https://\(config.host)", forHTTPHeaderField: "Origin")
        request.setValue(config.loginPageURL.absoluteString, forHTTPHeaderField: "Referer")
        request.httpBody = Self.formEncode(fields).data(using: .utf8)
        let (loginData, response) = try await session.data(for: request)
        let loginHTML = String(decoding: loginData, as: UTF8.self)
        let landingPath = response.url?.path ?? ""

        if debugLogResponses {
            // Never log the request body — it contains the password.
            print("↩︎ DoLogin → \(response.url?.absoluteString ?? "?") (\(Self.pageTitle(in: loginHTML) ?? "no title"))")
        }

        // Still being served the login form → bad credentials.
        if loginHTML.contains("id=\"loginForm\"") {
            throw MyChartError.loginFailed
        }
        // The portal's generic error page (e.g. Home/Error?code=15) — the
        // login was rejected before credentials were even checked.
        if landingPath.lowercased().hasSuffix("/home/error") {
            let code = response.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?
                .queryItems?.first { $0.name == "code" }?.value
            throw MyChartError.portalError(code: code)
        }
        pendingUsername = username

        // Epic's mid-login verification step (Authentication/SecondaryValidation).
        // Keep the half-signed-in session and let the UI drive sendCode/verify.
        if landingPath.lowercased().contains("secondaryvalidation") {
            twoFactor = Self.twoFactorContext(in: loginHTML)
            apiToken = Self.extractToken(from: loginHTML) ?? token
            throw MyChartError.twoFactorRequired
        }

        return try await finishSignIn(fallbackToken: token)
    }

    /// Completes sign-in once the portal has let us through to the app.
    private func finishSignIn(fallbackToken: String?) async throws -> PatientProfile {
        // The pre-login token is bound to the anonymous session and is rejected
        // once signed in. Signed-in pages embed the right one in
        // <div id='__CSRFContainer'><input name="__RequestVerificationToken" …>,
        // which is exactly the DOM node the site's API client reads. Loading
        // Home also mirrors the browser's post-login navigation.
        let (homeData, _) = try await session.data(from: config.url("Home"))
        let homeHTML = String(decoding: homeData, as: UTF8.self)

        if let token = Self.formInputs(in: homeHTML, containerID: "__CSRFContainer")["__RequestVerificationToken"],
           !token.isEmpty {
            apiToken = token
            if debugLogResponses { print("↩︎ CSRF token: from Home __CSRFContainer") }
        } else if let token = try await fetchCSRFToken() {
            apiToken = token
        } else {
            apiToken = fallbackToken
            if debugLogResponses { print("↩︎ No signed-in token found; using pre-login token") }
        }
        await reconcileDevice()
        twoFactor = nil
        if debugLogResponses { print("↩︎ Signed in (device \(Keychain.deviceID == nil ? "not remembered" : "remembered"))") }

        // In the browser, api/ calls carry _Host-MyChartAccessToken… (a JWT
        // from Interconnect) plus auth-ticket/session-token cookies. These look
        // to be issued when a React `app/…` page loads, which a plain Home load
        // doesn't do. Visit one the same way the browser does.
        // The browser's api/ calls carry a token that differs per `app/…`
        // page (letters vs health-summary), not Home's. Take the token from
        // the page we name as Referer, since Epic may bind it to that page.
        if let (appData, _) = try? await session.data(from: config.url("app/health-summary")) {
            let appHTML = String(decoding: appData, as: UTF8.self)
            let appToken = Self.formInputs(in: appHTML, containerID: "__CSRFContainer")["__RequestVerificationToken"]
                ?? Self.extractToken(from: appHTML)
            if let appToken, !appToken.isEmpty {
                if debugLogResponses { print("↩︎ CSRF token: from app/health-summary (\(appToken == apiToken ? "same as" : "differs from") Home's)") }
                apiToken = appToken
            } else if debugLogResponses {
                print("↩︎ CSRF token: none on app/health-summary (\(appData.count) bytes, title \(Self.pageTitle(in: appHTML) ?? "none"))")
            }
        }

        let username = pendingUsername ?? ""
        let subjects = await proxySubjects()
        let me = subjects.first(where: \.isSelf)
        let name = me?.name ?? username
        return PatientProfile(
            id: me.map(Self.accountID) ?? username,
            fullName: name,
            preferredName: name.split(separator: " ").first.map(String.init) ?? name,
            initials: Self.initials(of: name),
            linkedAccounts: subjects.map {
                LinkedAccount(id: Self.accountID($0), name: $0.name, initials: Self.initials(of: $0.name), unreadCount: 0)
            }
        )
    }

    // MARK: - Patient context (proxy switching)
    //
    // A parent account has its own (usually empty) chart plus one context per
    // child. Data endpoints act on whichever context the session is in, so the
    // right child must be selected before reading their record — otherwise the
    // endpoint fails with HTTP 500 and an empty body.

    /// One entry from the portal's account switcher.
    private struct ProxySubject {
        var id: String          // empty for the logged-in user
        var name: String
        var isSelf: Bool
        var linkURL: String
        var isSelected: Bool
    }

    private var subjectsCache: [ProxySubject] = []
    /// Account whose context the session is currently in.
    private var currentContextID: String?

    /// `GET ProxySwitch` — the same call the header's switcher uses.
    private func proxySubjects() async -> [ProxySubject] {
        var request = URLRequest(url: config.url("ProxySwitch"))
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, _) = try? await session.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = json["ProxySubjectList"] as? [[String: Any]] else {
            if debugLogResponses { print("↩︎ ProxySwitch: no account list") }
            return []
        }
        let subjects = list.map {
            ProxySubject(
                id: $0["Id"] as? String ?? "",
                name: $0["DisplayName"] as? String ?? "",
                isSelf: $0["IsSelf"] as? Bool ?? false,
                linkURL: $0["LinkUrl"] as? String ?? "",
                isSelected: $0["IsSelected"] as? Bool ?? false
            )
        }
        subjectsCache = subjects
        currentContextID = subjects.first(where: \.isSelected).map(Self.accountID)
        if debugLogResponses {
            print("↩︎ ProxySwitch: \(subjects.count) accounts, current = \(currentContextID ?? "none")")
        }
        return subjects
    }

    /// The switch in flight, so concurrent requests wait for it rather than
    /// each switching (and racing each other to a different account).
    private var contextSwitch: (id: String, task: Task<Void, Never>)?

    /// Switches the session to `patientID` if it isn't already there.
    private func ensureContext(_ patientID: String) async {
        guard !patientID.isEmpty else { return }
        // Wait out any switch already running, then re-check where we are.
        while let pending = contextSwitch {
            await pending.task.value
            if contextSwitch?.task == pending.task { contextSwitch = nil }
        }
        guard currentContextID != patientID else { return }

        let task = Task { await switchContext(to: patientID) }
        contextSwitch = (patientID, task)
        await task.value
        if contextSwitch?.task == task { contextSwitch = nil }
    }

    private func switchContext(to patientID: String) async {
        if subjectsCache.isEmpty { _ = await proxySubjects() }
        guard let subject = subjectsCache.first(where: { Self.accountID($0) == patientID }),
              !subject.linkURL.isEmpty else {
            if debugLogResponses { print("↩︎ Context: no account matching \(patientID)") }
            return
        }
        // LinkUrl is relative, e.g. inside.asp?mode=proxyswitch&action=switchcontext&eid=…
        let landing = try? await session.data(from: config.url(subject.linkURL)).1
        if debugLogResponses { print("↩︎ Context → \(subject.name) (landed at \(landing.map(Self.landingDescription) ?? "nowhere"))") }
        // In the browser the switch is a full page load, which hands out a
        // new anti-forgery token; the old one sends api/ calls to Home/Error.
        await refreshAPIToken()
        currentContextID = patientID
        contextGeneration += 1
    }

    /// Bumped on every switch, so a burst of requests failing together
    /// recovers with one switch rather than one each.
    private var contextGeneration = 0

    /// Re-reads the api/ token from the app page named as Referer, as at sign-in.
    private func refreshAPIToken() async {
        if let (data, _) = try? await session.data(from: config.url("app/health-summary")) {
            let html = String(decoding: data, as: UTF8.self)
            if let token = Self.formInputs(in: html, containerID: "__CSRFContainer")["__RequestVerificationToken"]
                ?? Self.extractToken(from: html), !token.isEmpty {
                if debugLogResponses { print("↩︎ CSRF token: refreshed from app/health-summary (\(token == apiToken ? "unchanged" : "changed"))") }
                apiToken = token
                return
            }
        }
        if let token = try? await fetchCSRFToken() { apiToken = token }
    }

    /// The portal answered with its error page: the session's context or token
    /// went stale. Switch again with a fresh account list (its links may have
    /// expired) and token, unless another request already did since `generation`.
    private func recoverContext(_ patientID: String, seenGeneration generation: Int) async {
        if generation == contextGeneration {
            if debugLogResponses { print("↩︎ Error page: switching context again") }
            subjectsCache = []
            currentContextID = nil
        }
        await ensureContext(patientID)
    }

    /// The portal's generic error page, e.g. Home/Error?code=15.
    private nonisolated static func isErrorPage(_ response: URLResponse) -> Bool {
        response.url?.path.lowercased().hasSuffix("/home/error") ?? false
    }

    /// Path plus any error code, for the log.
    private nonisolated static func landingDescription(_ response: URLResponse) -> String {
        guard let url = response.url else { return "?" }
        let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "code" }?.value
        return url.path + (code.map { "?code=\($0)" } ?? "")
    }

    /// The self entry has an empty Id; give it a stable stand-in.
    private nonisolated static func accountID(_ subject: ProxySubject) -> String {
        subject.id.isEmpty ? "self" : subject.id
    }

    private nonisolated static func initials(of name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        return parts.compactMap { $0.first }.map(String.init).joined().uppercased()
    }

    // MARK: - Two-factor verification
    //
    // Mirrors secondaryvalidationcontroller.js: SendCode posts which channel to
    // use, Validate posts the code plus the page's context flags. Both are
    // jQuery $.post calls, i.e. form-encoded with the CSRF header.

    enum CodeDelivery: Sendable {
        case email, sms
    }

    /// Settings the SecondaryValidation page hands its controller.
    struct TwoFactorContext: Sendable {
        var workflow = ""
        var isPostLogin2FA = false
        var enrollDeviceTrackingOnRemember = false
    }

    func sendVerificationCode(via delivery: CodeDelivery, resend: Bool = false) async throws {
        let context = twoFactor ?? TwoFactorContext()
        let key = delivery == .email ? "deliveryMethodEmail" : "deliveryMethodSMS"
        let json = try await postForm("Authentication/SecondaryValidation/SendCode", fields: [
            key: "true",
            "resendCode": resend ? "true" : "false",
            "workflow": context.workflow
        ])
        guard json["Success"] as? Bool == true else { throw MyChartError.codeSendFailed }
    }

    func verifyCode(_ code: String, rememberDevice: Bool) async throws -> PatientProfile {
        let context = twoFactor ?? TwoFactorContext()
        let json = try await postForm("Authentication/SecondaryValidation/Validate", fields: [
            "TwoFactorCode": code,
            "RememberMe": rememberDevice ? "checked" : "",
            "IsPostLogin2FA": context.isPostLogin2FA ? "true" : "false",
            "EnrollDeviceTrackingOnRemember": context.enrollDeviceTrackingOnRemember ? "true" : "false",
            "DeviceId": Keychain.deviceID ?? "",
            "Workflow": context.workflow,
            "isTOTP": "false"
        ])
        guard json["Success"] as? Bool == true else {
            let expired = (json["TwoFactorCodeFailReason"] as? String) == "codeexpiredtf"
            throw MyChartError.invalidCode(expired: expired)
        }
        // Same as `_setDeviceInStorageIfEmpty`: this ID is what skips the
        // code on future logins when "remember" was ticked.
        if Keychain.deviceID == nil, let id = json["RememberDeviceId"] as? String, !id.isEmpty {
            Keychain.deviceID = id
        }

        // The page's success callback navigates to Home, which finishSignIn does.
        return try await finishSignIn(fallbackToken: apiToken)
    }

    /// Reads the controller context out of the SecondaryValidation page's
    /// inline script. Defaults match `_initializeDefaultSettings`.
    nonisolated static func twoFactorContext(in html: String) -> TwoFactorContext {
        func capture(_ pattern: String) -> String? {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
                  let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                  let r = Range(match.range(at: 1), in: html) else { return nil }
            return String(html[r])
        }
        var context = TwoFactorContext()
        context.workflow = capture(#"["']?Workflow["']?\s*:\s*["']?(\w+)"#) ?? ""
        context.isPostLogin2FA = capture(#"["']?IsPostLogin2FA["']?\s*:\s*(true|false)"#) == "true"
        let rememberEnabled = capture(#"RememberMeSettings["']?\s*:\s*\{[^}]*?["']?Enabled["']?\s*:\s*(true|false)"#) == "true"
        let enrollTracking = capture(#"["']?EnrollDeviceTracking["']?\s*:\s*(true|false)"#) == "true"
        context.enrollDeviceTrackingOnRemember = rememberEnabled && enrollTracking
        return context
    }

    // MARK: - Data endpoints

    /// MRNs never change, so each is fetched once per session.
    private var headerCache: [String: RecordHeader] = [:]

    func recordHeader(for patientID: String) async throws -> RecordHeader {
        if let cached = headerCache[patientID] { return cached }
        // Home's print header names the patient whose context we're in:
        // <div class="printheader">Name: … | DOB: … | MRN: 12345678 | …</div>
        // (RCH calls the MRN a UR number.)
        await ensureContext(patientID)
        let (data, _) = try await session.data(from: config.url("Home"))
        let html = String(decoding: data, as: UTF8.self)
        if html.contains("Authentication/Login") { throw MyChartError.sessionExpired }
        let header = Self.recordHeader(in: html)
        if debugLogResponses, header.urNumber == nil { print("↩︎ UR number: not found on Home") }
        if header.urNumber != nil || header.fullName != nil { headerCache[patientID] = header }
        return header
    }

    /// Reads only the Name and MRN fields from the print header, not the rest.
    nonisolated static func recordHeader(in html: String) -> RecordHeader {
        guard let range = html.range(of: #"class="printheader"[^>]*>[^<]*"#, options: .regularExpression) else {
            return RecordHeader()
        }
        let header = html[range]
        func field(_ name: String) -> String? {
            guard let match = header.range(of: name + #":\s*[^|<]+"#, options: .regularExpression) else { return nil }
            let value = header[match].dropFirst(name.count + 1).trimmingCharacters(in: .whitespaces)
            return value.isEmpty ? nil : value
        }
        return RecordHeader(fullName: field("Name").map(displayName), urNumber: field("MRN"))
    }

    /// "ANDERSON, Sallie" → "Sallie Anderson"; "Sallie Anderson" is kept.
    /// The header's exact format hasn't been seen, so handle both.
    nonisolated static func displayName(_ raw: String) -> String {
        var name = raw.trimmingCharacters(in: .whitespaces)
        let parts = name.split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.count == 2, !parts[1].isEmpty { name = parts[1] + " " + parts[0] }
        // All-caps words become title case; mixed case (e.g. "McKenzie") stays.
        return name.split(separator: " ").map { word in
            word == word.uppercased() && word.count > 1 ? word.prefix(1) + word.dropFirst().lowercased() : word
        }.joined(separator: " ")
    }

    func appointments(for patientID: String) async throws -> [Appointment] {
        // Visits predate the api/ endpoints: two legacy MVC actions, one for
        // upcoming and one for past, with their parameters in the query string.
        async let upcoming = postLegacy(for: patientID, path: "Visits/VisitsList/LoadUpcoming", query: [
            "timeZone": TimeZone.current.identifier,
            "ComponentNumber": "5"
        ])
        async let past = postLegacy(for: patientID, path: "Visits/VisitsList/LoadPast", query: [
            "loadpast": "1",
            "searchString": "",
            "oldestRenderedDate": ISO8601DateFormatter().string(from: .now),
            "ComponentNumber": "7"
        ], form: ["serializedIndex": ""])

        // One list failing shouldn't hide the other, but if both fail, surface
        // the error instead of showing an empty (misleading) list.
        var upcomingJSON: Any?, pastJSON: Any?, failure: Error?
        do { upcomingJSON = try await upcoming } catch { failure = error }
        do { pastJSON = try await past } catch { failure = error }
        if upcomingJSON == nil, pastJSON == nil, let failure { throw failure }

        let scheduled = decodeAppointments(upcomingJSON, status: .scheduled)
        let completed = decodeAppointments(pastJSON, status: .completed)
        return scheduled + completed
    }

    func testResults(for patientID: String) async throws -> [TestResult] {
        // Captured from the site's test-results page. maxResults 0 means "no
        // limit". The orgFeatureFlags key is an opaque organisation ID; it's
        // sent verbatim because the site always includes it.
        let json = try await postJSON(for: patientID, action: "api/test-results/GetList", body: [
            "groupType": "UNINITIALIZED",
            "searchString": "",
            "maxResults": 0,
            "isCurAdmFilterEnabled": false,
            "startDate": "",
            "endDate": "",
            "orgFeatureFlags": [
                "WP-24QZ0-2BNFMpjsT9T6CEbrt0xg-3D-3D-24gE889As1b2-2FfzbE-2BLSErCngBdpQyABaMP-2Bq7U-2BrwKOE-3D": [
                    "hasGrouping": false,
                    "hasDateRangeFilterProperties": true
                ]
            ]
        ])
        return decodeTestResults(json)
    }

    /// Details already fetched, keyed by patient and result. Filled by list
    /// rows as they appear, so opening a result doesn't fetch it again.
    private var detailsCache: [String: TestResult] = [:]

    func testResultDetails(_ result: TestResult, for patientID: String) async throws -> TestResult {
        let cacheKey = "\(patientID)|\(result.id)"
        if let cached = detailsCache[cacheKey] { return cached }
        let detailed = try await fetchTestResultDetails(result, for: patientID)
        // Only final results are settled; preliminary ones can still change.
        if detailed.status.localizedCaseInsensitiveCompare("Final") == .orderedSame {
            detailsCache[cacheKey] = detailed
        }
        return detailed
    }

    private func fetchTestResultDetails(_ result: TestResult, for patientID: String) async throws -> TestResult {
        // Captured from the site's result-details page. orderKey is the
        // result's `key` from GetList. The site sends a fresh PageNonce per page
        // load; a generated one is accepted (HTTP 200), so it isn't validated.
        let json = try await postJSON(for: patientID, action: "api/test-results/GetDetails", body: [
            "organizationID": "",
            "orderKey": result.id,
            "PageNonce": UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        ])
        var detailed = decodeTestResultDetails(json, into: result)

        // Imaging reports aren't in GetDetails: it only names a report
        // (reportDetails.reportID + reportVars) for LoadReportContent to render.
        if detailed.summary == nil, let report = Self.reportReference(json) {
            do {
                detailed.summary = try await reportText(for: patientID, reportID: report.id, variables: report.variables)
            } catch {
                // Keep the rest of the details; the view explains the gap.
                if debugLogResponses { print("   LoadReportContent failed: \(error.localizedDescription)") }
            }
        }
        return detailed
    }

    /// A past visit's care-team notes and After Visit Summary. The appointment
    /// id is the visit's `Csn` from the visits list.
    ///
    /// GetVisitDetailsPast says what the visit has: `avsInfo` names the AVS
    /// report and its language, and `notesInfo` says whether any note is
    /// shareable, so GetVisitNotes is only called when there's something to list.
    func visitDocuments(appointmentID csn: String, for patientID: String) async throws -> [VisitDocument] {
        // Captured from the past-visit page.
        let details = try await postJSON(for: patientID, action: "api/visits/past-details/GetVisitDetailsPast",
                                         body: ["csn": csn, "eorgID": ""]) as? [String: Any] ?? [:]
        let notesInfo = details["notesInfo"] as? [String: Any] ?? [:]
        let hasNotes = notesInfo["isAtLeastOneNoteShareable"] as? Bool ?? true
        let notes = hasNotes ? try await visitNotes(csn: csn, for: patientID) : []
        return notes + Self.afterVisitSummary(in: details, csn: csn)
    }

    /// The visit's After Visit Summary, if it has a shareable one. PDF-only
    /// summaries (`isEmbeddedPdfReport`) aren't handled yet.
    private nonisolated static func afterVisitSummary(in details: [String: Any], csn: String) -> [VisitDocument] {
        guard let avs = details["avsInfo"] as? [String: Any],
              avs["hasShareableAvs"] as? Bool ?? false,
              let primary = avs["primaryAvs"] as? [String: Any],
              let reportID = string(primary, "reportID"),
              !(primary["isEmbeddedPdfReport"] as? Bool ?? false) else { return [] }
        // The language the portal suggests, else the first offered.
        let languages = avs["languages"] as? [[String: Any]] ?? []
        let language = languages.first { $0["suggested"] as? Bool ?? false } ?? languages.first
        var parameters = ["reportID": reportID, "csn": csn]
        if let languageID = language.flatMap({ string($0, "languageID") }) { parameters["contextLang"] = languageID }
        return [VisitDocument(id: "avs-\(csn)", kind: .afterVisitSummary,
                              title: string(primary, "reportName") ?? "After Visit Summary",
                              reportParameters: parameters)]
    }

    /// Each care-team note on a visit, from GetVisitNotes.
    private func visitNotes(csn: String, for patientID: String) async throws -> [VisitDocument] {
        let json = try await postJSON(for: patientID, action: "api/visit-notes/GetVisitNotes",
                                      body: ["CSN": csn, "FromPvdPage": true])
        guard let response = json as? [String: Any],
              let reportID = Self.string(response, "lrpID") else { return [] }
        let notes = response["noteList"] as? [[String: Any]] ?? []
        return notes.compactMap { note in
            guard let hnoID = Self.string(note, "hnoID"), let hnoDAT = Self.string(note, "hnoDAT") else { return nil }
            let name = Self.string(note, "displayName") ?? "Note"
            return VisitDocument(
                id: hnoID,
                kind: .careTeamNotes,
                title: (note["isAddendum"] as? Bool ?? false) ? "\(name) (addendum)" : name,
                author: Self.string(note["provider"] as? [String: Any] ?? [:], "name"),
                date: Self.string(note, "iso").flatMap(ISO8601DateFormatter().date(from:)),
                // As the site sends it: the note's HNO record, by id and date.
                reportParameters: ["reportID": reportID, "contextID": hnoID, "contextDAT": hnoDAT,
                                   "contextINI": "HNO", "csn": csn]
            )
        }
    }

    // MARK: Letters

    /// Captured from the letters page: body `{}`. Authors are looked up in
    /// the response's `users` dictionary by `empId`.
    func letters(for patientID: String) async throws -> [Letter] {
        let json = try await postJSON(for: patientID, action: "api/letters/GetLettersList")
        guard let response = json as? [String: Any] else { return [] }
        let users = response["users"] as? [String: [String: Any]] ?? [:]
        let items = response["letters"] as? [[String: Any]] ?? []
        return items.compactMap { item in
            guard let id = Self.string(item, "hnoId"), let csn = Self.string(item, "csn"),
                  let date = Self.string(item, "dateISO").flatMap(Self.isoDay) else { return nil }
            let author = Self.string(item, "empId").flatMap { users[$0] }.flatMap { Self.string($0, "name") }
            return Letter(id: id, csn: csn, date: date,
                          reason: Self.string(item, "reason") ?? "",
                          author: author,
                          isUnread: !(item["viewed"] as? Bool ?? true))
        }
        .sorted { $0.date > $1.date }
    }

    /// Captured from the letter page. `bodyHTML` is the letter as
    /// Word-converted HTML with its own inline styles; like PageNonce
    /// elsewhere, a generated nonce is accepted.
    func letterHTML(_ letter: Letter, for patientID: String) async throws -> String {
        let json = try await postJSON(for: patientID, action: "api/letters/GetLetterDetails", body: [
            "hnoId": letter.id,
            "csn": letter.csn,
            "PageNonce": UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        ])
        guard let response = json as? [String: Any], let body = Self.string(response, "bodyHTML") else {
            throw MyChartError.decoding(action: "GetLetterDetails", snippet: "no bodyHTML")
        }
        return Self.reportPage(content: body, css: "", stylesheets: [], scope: "letter")
    }

    /// A past visit's After Visit Summary or care-team note, from the same
    /// LoadReportContent endpoint as imaging reports. The body is the
    /// document's own parameters (captured from the past-visit page), plus
    /// the same page-scoping fields.
    func visitDocumentHTML(_ document: VisitDocument, for patientID: String) async throws -> String {
        let scope = "EID-app"
        var body: [String: Any] = document.reportParameters
        body["isFullReportPage"] = false
        body["uniqueClass"] = scope
        body["nonce"] = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let json = try await postJSON(for: patientID, action: "api/report-content/LoadReportContent", body: body)
        guard let response = json as? [String: Any], let content = Self.string(response, "reportContent") else {
            throw MyChartError.decoding(action: "LoadReportContent", snippet: "no reportContent")
        }
        return Self.reportPage(content: content,
                               css: Self.string(response, "reportCss") ?? "",
                               stylesheets: response["stylesheets"] as? [String] ?? [],
                               scope: scope)
    }

    /// Wraps LoadReportContent's pieces into one page. `reportCss` is nested
    /// under `.<scope>{…}`, so the content sits inside an element with that
    /// class. Stylesheet paths are host-relative (`/MyRCHPortal/…`); the
    /// viewer loads the page with the portal as its base URL.
    private nonisolated static func reportPage(content: String, css: String, stylesheets: [String], scope: String) -> String {
        // JavaScript is off in the viewer too; this is belt and braces.
        let safeContent = content.replacingOccurrences(
            of: #"<script\b[\s\S]*?</script>"#, with: "", options: [.regularExpression, .caseInsensitive])
        let links = stylesheets.map { "<link rel=\"stylesheet\" href=\"\($0)\">" }.joined(separator: "\n")
        return """
        <!DOCTYPE html>
        <html><head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="color-scheme" content="light">
        \(links)
        \(css)
        <style>body { margin: 0; padding: 12px; background: #fff; -webkit-text-size-adjust: 100%; }</style>
        </head><body><div class="\(scope)">\(safeContent)</div></body></html>
        """
    }

    /// Captured from the site. uniqueClass and nonce scope the returned CSS
    /// to the page; the site makes them up per page, so any value works.
    private func reportText(for patientID: String, reportID: String, variables: [String: Any]) async throws -> String? {
        let json = try await postJSON(for: patientID, action: "api/report-content/LoadReportContent", body: [
            "reportID": reportID,
            "assumedVariables": variables,
            "isFullReportPage": false,
            "uniqueClass": "EID-app",
            "nonce": UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        ])
        guard let html = (json as? [String: Any]).flatMap({ Self.string($0, "reportContent") }) else { return nil }
        // Drop the report's own section headings; the card already says "Report".
        let boilerplate: Set<String> = ["Study Result", "Narrative & Impression"]
        let text = Self.plainText(fromHTML: html)
            .components(separatedBy: "\n")
            .filter { !boilerplate.contains($0.trimmingCharacters(in: .whitespaces)) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// The first non-empty reportDetails.reportID in a GetDetails response.
    private nonisolated static func reportReference(_ json: Any) -> (id: String, variables: [String: Any])? {
        let items = (json as? [String: Any])?["results"] as? [[String: Any]] ?? []
        for item in items {
            guard let details = item["reportDetails"] as? [String: Any],
                  let id = string(details, "reportID") else { continue }
            return (id, details["reportVars"] as? [String: Any] ?? [:])
        }
        return nil
    }

    func documentData(_ document: ResultDocument, for patientID: String) async throws -> Data {
        guard let path = document.downloadPath,
              let url = URL(string: "https://\(config.host)\(config.basePath)\(path)") else {
            throw MyChartError.decoding(action: "document", snippet: "no download path")
        }
        await ensureContext(patientID)
        // A plain link on the site, so GET with the page as Referer.
        var request = URLRequest(url: url)
        request.setValue(config.url("app/test-results").absoluteString, forHTTPHeaderField: "Referer")
        let (data, response) = try await session.data(for: request)
        let mimeType = response.mimeType ?? "?"
        if debugLogResponses {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            print("→ document: HTTP \(status), \(mimeType), \(data.count) bytes")
        }
        // An expired session answers with the login page instead of the file.
        if mimeType == "text/html" {
            let text = String(decoding: data.prefix(4096), as: UTF8.self)
            if text.contains("Authentication/Login") { throw MyChartError.sessionExpired }
            throw MyChartError.decoding(action: "document", snippet: Self.pageTitle(in: text) ?? "HTML page")
        }
        return data
    }

    func medications(for patientID: String) async throws -> [Medication] {
        // Captured from the site: the health-summary page posts {"context":2}
        // (matches `communityMembers[].context` in the response). An empty
        // body gets HTTP 500.
        let json = try await postJSON(for: patientID, action: "api/medications/LoadMedicationsPage", body: ["context": 2])
        return decodeMedications(json)
    }

    /// Captured from the Add Medication page: `{searchString, genericOnly,
    /// resultsLimit, isRxNorm, isCommon, isForSearchAsYouType}` →
    /// `{results: [{id, name, isPreferred}], searchFinished, …}`. The portal
    /// may return a few more than `resultsLimit`.
    func searchMedications(_ text: String, for patientID: String) async throws -> [MedicationSearchResult] {
        let json = try await postJSON(for: patientID, action: "api/medications/SearchMedications", body: [
            "searchString": text,
            "genericOnly": false,
            "resultsLimit": 20,
            "isRxNorm": false,
            "isCommon": false,
            "isForSearchAsYouType": false
        ], savesCopy: false, referer: config.url("app/medications/add-medication").absoluteString)
        let results = (json as? [String: Any])?["results"] as? [[String: Any]] ?? []
        return results.compactMap { item in
            guard let id = Self.string(item, "id"), let name = Self.string(item, "name") else { return nil }
            return MedicationSearchResult(id: id, name: name)
        }
    }

    /// Captured from the Add Medication page: `{"updateType": 1, "name": …,
    /// "erxID": "", "date": "2026-09-18"}`. Only a free-text name has been
    /// captured (erxID empty), so a picked search result is sent by name too.
    /// `date` is when they started taking it, as a Melbourne calendar day.
    func addMedication(named name: String, startDate: Date, for patientID: String) async throws {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Australia/Melbourne")
        formatter.dateFormat = "yyyy-MM-dd"
        let json = try await postJSON(for: patientID, action: "api/medications/SubmitMedicationUpdate", body: [
            "updateType": 1,
            "name": name,
            "erxID": "",
            "date": formatter.string(from: startDate)
        ], savesCopy: false, referer: config.url("app/medications/add-medication").absoluteString)
        // The reply hasn't been captured, so only an explicit failure counts.
        let reply = json as? [String: Any] ?? [:]
        if reply["isSuccess"] as? Bool == false || !(reply["errors"] as? [Any] ?? []).isEmpty {
            throw MyChartError.actionFailed("SubmitMedicationUpdate")
        }
    }

    /// Captured from the Medications page, removing a medication the family
    /// added (still awaiting review): a legacy form POST to
    /// `Clinical/Medications/SubmitUpdate?noCache=…` with `name` (the
    /// portal's raw name), `action=4`, `referenceID` and
    /// `IsFilteredList=false`. `referenceID`
    /// is the pending update's `updateInformation.referenceID`, not the
    /// medication's `id`. A refusal answers `{"success": false}`. Success is
    /// also checked by reloading the list and making sure it has gone.
    func removeMedication(_ medication: Medication, for patientID: String) async throws {
        // Only pending additions carry the id; anything else can't be
        // removed this way.
        guard let referenceID = medication.updateReferenceID else {
            throw MyChartError.actionFailed("SubmitUpdate")
        }
        await ensureContext(patientID)
        let path = "Clinical/Medications/SubmitUpdate"
        var components = URLComponents(url: config.url(path), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "noCache", value: String(Double.random(in: 0..<1)))]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue("https://\(config.host)", forHTTPHeaderField: "Origin")
        request.setValue(config.url("Clinical/Medications").absoluteString, forHTTPHeaderField: "Referer")
        if let apiToken { request.setValue(apiToken, forHTTPHeaderField: "__RequestVerificationToken") }
        request.httpBody = Self.formEncode([
            "name": medication.portalName ?? medication.sourceName ?? medication.name,
            "action": "4",
            "referenceID": referenceID,
            "IsFilteredList": "false"
        ]).data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if debugLogResponses { print("→ \(path): HTTP \(status), \(data.count) bytes") }
        let text = String(decoding: data, as: UTF8.self)
        if text.contains("Authentication/Login") { throw MyChartError.sessionExpired }
        guard (200..<300).contains(status) else { throw MyChartError.actionFailed("SubmitUpdate") }
        if let reply = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           reply["success"] as? Bool == false {
            throw MyChartError.actionFailed("SubmitUpdate")
        }

        // The portal answered, but only a fresh list without it proves it's
        // gone. Drop the device's saved list too, so it doesn't come back.
        let body: [String: Any] = ["context": 2]
        PortalDiskCache.shared.remove(PortalDiskCache.shared.key(
            patientID: patientID, endpoint: "api/medications/LoadMedicationsPage", parameters: body))
        let json = try await postJSON(for: patientID, action: "api/medications/LoadMedicationsPage",
                                      body: body, savesCopy: false)
        if decodeMedications(json).contains(where: { $0.id == medication.id && $0.isActive }) {
            throw MyChartError.actionFailed("SubmitUpdate")
        }
    }

    /// Latest message of each conversation, for the dashboard and notifications.
    func messages(for patientID: String) async throws -> [Message] {
        try await conversations(for: patientID).compactMap { conversation in
            guard let last = conversation.messages.last else { return nil }
            return Message(id: conversation.id, subject: conversation.subject,
                           sender: last.isFromMe ? "You" : last.authorName,
                           preview: last.body, date: last.date, isUnread: conversation.isUnread)
        }
    }

    /// Captured from the Messages page. `tag` picks the folder (1 inbox,
    /// 2 Trash, 3 Bookmarked); `pagingInfo` and the load window page back
    /// through older conversations (`localSummary.hasMoreConversations`),
    /// which isn't done yet.
    func conversations(in folder: MessageFolder, for patientID: String) async throws -> [Conversation] {
        let json = try await postJSON(for: patientID, action: "api/conversations/GetConversationList",
                                      body: Self.listBody(folder))
        guard let root = json as? [String: Any] else { return [] }
        let people = Self.conversationPeople(root)
        return (root["conversations"] as? [[String: Any]] ?? []).compactMap { Self.decodeConversation($0, people: people) }
    }

    /// One thread in full, as the portal's conversation page loads it (which
    /// also marks it read there). Adds when staff last viewed it.
    func conversation(id: String, for patientID: String) async throws -> Conversation {
        let json = try await postJSON(for: patientID, action: "api/conversations/GetConversationDetails", body: [
            "id": id, "messageId": "", "organizationId": "",
            "PageNonce": UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        ])
        guard let root = json as? [String: Any],
              let conversation = Self.decodeConversation(root, people: Self.conversationPeople(root)) else {
            throw MyChartError.decoding(action: "GetConversationDetails", snippet: "no conversation")
        }
        return conversation
    }

    private nonisolated static func listBody(_ folder: MessageFolder) -> [String: Any] {
        [
            "tag": folder.rawValue,
            "localLoadParams": ["loadStartInstantISO": "", "loadEndInstantISO": "", "pagingInfo": 1],
            "externalLoadParams": [String: Any](),
            "searchQuery": "",
            "PageNonce": UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        ]
    }

    // Captured from the conversation page's menu and the list's multi-select.
    // Single actions (Bookmark, RemoveBookmark, MoveToTrash, RestoreFromTrash)
    // are separate endpoints, not toggles. BulkConversationAction has been
    // captured with BulkUnread, BulkRemoveBookmark and BulkMoveToTrash only,
    // so bookmarking and restoring several send one request each.

    func setConversationsBookmarked(_ isBookmarked: Bool, ids: [String], for patientID: String) async throws {
        if isBookmarked || ids.count == 1 {
            for id in ids {
                try await conversationAction(isBookmarked ? "Bookmark" : "RemoveBookmark", id: id, for: patientID)
            }
        } else {
            try await bulkAction("BulkRemoveBookmark", ids: ids, for: patientID)
        }
    }

    /// Unread goes through BulkUnread. There's no captured "mark read"; the
    /// portal marks a thread read when its details load, so do just that.
    func setConversationsUnread(_ isUnread: Bool, ids: [String], for patientID: String) async throws {
        if isUnread {
            try await bulkAction("BulkUnread", ids: ids, for: patientID)
            return
        }
        for id in ids {
            _ = try await postJSON(for: patientID, action: "api/conversations/GetConversationDetails",
                                   body: Self.detailsBody(id), savesCopy: false)
        }
        forgetSavedConversations(ids, for: patientID)
    }

    /// The portal's "archive" is its Trash folder; RestoreFromTrash undoes it.
    func moveConversationsToTrash(ids: [String], for patientID: String) async throws {
        if ids.count == 1, let id = ids.first {
            try await conversationAction("MoveToTrash", id: id, for: patientID)
        } else {
            try await bulkAction("BulkMoveToTrash", ids: ids, for: patientID)
        }
    }

    func restoreConversationsFromTrash(ids: [String], for patientID: String) async throws {
        for id in ids {
            try await conversationAction("RestoreFromTrash", id: id, for: patientID)
        }
    }

    /// Body `{conversationId, organizationId: ""}`; the reply is
    /// `{conversationId, isSuccess, errors, warnings}`.
    private func conversationAction(_ action: String, id: String, for patientID: String) async throws {
        defer { forgetSavedConversations([id], for: patientID) }
        let json = try await postJSON(for: patientID, action: "api/conversations/\(action)",
                                      body: ["conversationId": id, "organizationId": ""], savesCopy: false,
                                      referer: Self.conversationPage(id))
        guard (json as? [String: Any])?["isSuccess"] as? Bool == true else {
            throw MyChartError.actionFailed(action)
        }
    }

    /// Body `{Conversations: [{conversationId, organizationId: ""}], actionType}`.
    /// The reply hasn't been captured, so only an explicit failure counts
    /// (`isSuccess: false`, or any `errors`).
    private func bulkAction(_ actionType: String, ids: [String], for patientID: String) async throws {
        defer { forgetSavedConversations(ids, for: patientID) }
        let json = try await postJSON(for: patientID, action: "api/conversations/BulkConversationAction", body: [
            "Conversations": ids.map { ["conversationId": $0, "organizationId": ""] },
            "actionType": actionType
        ], savesCopy: false, referer: config.url("app/communication-center").absoluteString)
        let reply = json as? [String: Any] ?? [:]
        if reply["isSuccess"] as? Bool == false || !(reply["errors"] as? [Any] ?? []).isEmpty {
            throw MyChartError.actionFailed(actionType)
        }
    }

    /// Captured from the conversation page's reply box:
    /// 1. GetComposeId `{}` → a bare JSON string, the draft's `WP-…` id
    /// 2. SaveReplyDraft, then SendReply with the same body; SendReply
    ///    answers with a bare string, the conversation's id
    /// 3. RemoveComposeId `{composeId}` releases the id (answers a string)
    /// Discarding uses DeleteReplyDraft `{conversationId, organizationId}`.
    /// `viewers` is the signed-in family member. `messageBody` is an array;
    /// only one-line replies have been captured, so one entry per line is
    /// the best reading of it, not a verified one.
    func sendReply(_ text: String, attachments: [MessageAttachment], in conversation: Conversation,
                   includeOtherViewers: Bool, for patientID: String) async throws {
        guard let viewerID = conversation.replyViewerID else { throw MyChartError.actionFailed("SendReply") }
        let referer = Self.conversationPage(conversation.id)
        let composeJSON = try await postJSON(for: patientID, action: "api/conversations/GetComposeId",
                                             savesCopy: false, referer: referer)
        guard let composeID = composeJSON as? String, !composeID.isEmpty else {
            throw MyChartError.actionFailed("GetComposeId")
        }
        let body: [String: Any] = [
            "conversationId": conversation.id,
            "organizationId": "",
            "viewers": [["wprId": viewerID]],
            "messageBody": text.components(separatedBy: .newlines),
            "documentIds": attachments.map(\.id),
            "includeOtherViewers": includeOtherViewers,
            "composeId": composeID
        ]
        defer { forgetSavedConversations([conversation.id], for: patientID) }
        do {
            _ = try await postJSON(for: patientID, action: "api/conversations/SaveReplyDraft", body: body,
                                   savesCopy: false, referer: referer)
            let json = try await postJSON(for: patientID, action: "api/conversations/SendReply", body: body,
                                          savesCopy: false, referer: referer)
            guard let sentTo = json as? String, !sentTo.isEmpty else {
                throw MyChartError.actionFailed("SendReply")
            }
        } catch {
            // Don't leave a half-finished draft on the portal.
            _ = try? await postJSON(for: patientID, action: "api/conversations/DeleteReplyDraft",
                                    body: ["conversationId": conversation.id, "organizationId": ""],
                                    savesCopy: false, referer: referer)
            _ = try? await postJSON(for: patientID, action: "api/conversations/RemoveComposeId",
                                    body: ["composeId": composeID], savesCopy: false, referer: referer)
            throw error
        }
        // Tidy-up only; the reply has already gone.
        _ = try? await postJSON(for: patientID, action: "api/conversations/RemoveComposeId",
                                body: ["composeId": composeID], savesCopy: false, referer: referer)
    }

    /// Captured from the reply box's attach button: a multipart POST to
    /// DocumentUpload/UploadFile. The file goes in `__file__[]`, with the
    /// site's fixed fields (`DCSSource` 820, pending, cached) and the CSRF
    /// token repeated as a field. Answers `{Success, Data: [{DocumentId,
    /// FileDisplayName, …}]}`; `DocumentId` goes in the reply's `documentIds`.
    func uploadAttachment(_ data: Data, fileName: String, mimeType: String,
                          for patientID: String) async throws -> MessageAttachment {
        await ensureContext(patientID)
        let boundary = "----myRCHFormBoundary\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        var body = Data()
        func append(_ text: String) { body.append(Data(text.utf8)) }
        let safeName = fileName.replacingOccurrences(of: "\"", with: "'")
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"__file__[]\"; filename=\"\(safeName)\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(data)
        append("\r\n")
        let fields: [(String, String)] = [
            ("AddDCSToCache", "true"), ("IsPending", "true"), ("DCSSource", "820"),
            ("TargetPatientID", ""), ("OrganizationId", ""), ("EncryptDCSOnRemote", ""),
            ("__RequestVerificationToken", apiToken ?? "")
        ]
        for (name, value) in fields {
            append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n")
        }
        append("--\(boundary)--\r\n")

        var request = URLRequest(url: config.url("DocumentUpload/UploadFile"))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("https://\(config.host)", forHTTPHeaderField: "Origin")
        request.setValue(config.url("app/communication-center").absoluteString, forHTTPHeaderField: "Referer")
        if let apiToken { request.setValue(apiToken, forHTTPHeaderField: "__RequestVerificationToken") }
        request.httpBody = body

        let (reply, response) = try await session.data(for: request)
        if debugLogResponses {
            print("→ DocumentUpload/UploadFile: HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        guard let json = try? JSONSerialization.jsonObject(with: reply) as? [String: Any] else {
            if String(decoding: reply.prefix(2000), as: UTF8.self).contains("Authentication/Login") {
                throw MyChartError.sessionExpired
            }
            throw MyChartError.actionFailed("UploadFile")
        }
        guard json["Success"] as? Bool == true,
              let file = (json["Data"] as? [[String: Any]])?.first,
              let documentID = Self.string(file, "DocumentId") else {
            throw MyChartError.actionFailed("UploadFile")
        }
        return MessageAttachment(id: documentID, name: Self.string(file, "FileDisplayName") ?? fileName)
    }

    /// The conversation page, which the site sends as Referer for its actions.
    private nonisolated static func conversationPage(_ id: String) -> String {
        var components = URLComponents(string: MyChartConfig().url("app/communication-center/conversation").absoluteString)
        components?.queryItems = [URLQueryItem(name: "id", value: id)]
        return components?.url?.absoluteString ?? MyChartConfig().url("app/communication-center").absoluteString
    }

    private nonisolated static func detailsBody(_ id: String) -> [String: Any] {
        ["id": id, "messageId": "", "organizationId": "",
         "PageNonce": UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()]
    }

    /// Saved copies of the folders and threads would show the old state.
    private func forgetSavedConversations(_ ids: [String], for patientID: String) {
        let disk = PortalDiskCache.shared
        for folder in MessageFolder.allCases {
            disk.remove(disk.key(patientID: patientID, endpoint: "api/conversations/GetConversationList",
                                 parameters: Self.listBody(folder)))
        }
        for id in ids {
            disk.remove(disk.key(patientID: patientID, endpoint: "api/conversations/GetConversationDetails",
                                 parameters: Self.detailsBody(id)))
        }
    }

    func careTeam(for patientID: String) async throws -> [CareTeamMember] {
        let json = try await postJSON(for: patientID, action: "api/conversations/GetRecipients")
        return decodeCareTeam(json)
    }

    /// Captured from the growth-charts page: body `{}`. One response holds
    /// every reference set (curves included) and the child's measurements.
    func growthCharts(for patientID: String) async throws -> [GrowthDataset] {
        let json = try await postJSON(for: patientID, action: "api/growth-charts/GetGrowthCharts")
        return Self.decodeGrowth(json)
    }

    func healthIssues(for patientID: String) async throws -> [HealthIssue] {
        // Captured from the health-summary page.
        let json = try await postJSON(for: patientID, action: "api/HealthIssues/LoadHealthIssuesData",
                                      body: ["isHealthSummary": true])
        return decodeHealthIssues(json)
    }

    func allergies(for patientID: String) async throws -> [Allergy] {
        let json = try await postJSON(for: patientID, action: "api/allergies/LoadAllergies")
        return decodeAllergies(json)
    }

    func immunisations(for patientID: String) async throws -> [Immunisation] {
        let json = try await postJSON(for: patientID, action: "api/immunizations/LoadImmunizations")
        return decodeImmunisations(json)
    }

    /// Captured from the health summary's Goals panel: `{PageNonce}` →
    /// `{patientGoals: [{text, goalId, lastUpdatedDate: "28 Sep, 2026", …}]}`.
    func patientGoals(for patientID: String) async throws -> [PortalGoal] {
        let json = try await postJSON(for: patientID, action: "api/goals/LoadPatientGoals", body: [
            "PageNonce": UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        ], savesCopy: false)
        let goals = (json as? [String: Any])?["patientGoals"] as? [[String: Any]] ?? []
        return goals.compactMap { goal in
            Self.string(goal, "text").map { PortalGoal(text: $0, lastUpdated: Self.string(goal, "lastUpdatedDate")) }
        }
    }

    /// Captured from the Goals panel: `{"key": 0, "goal": {"lastUpdatedDate":
    /// "28 Sep 2026", "text": "…"}}`. The portal has a single free-text goal,
    /// so `key` 0 is that goal and saving replaces it. Saving empty text
    /// clears it, as the portal's own panel does.
    func setPatientGoal(_ text: String, for patientID: String) async throws {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_AU")
        formatter.timeZone = TimeZone(identifier: "Australia/Melbourne")
        formatter.dateFormat = "d MMM yyyy"
        let json = try await postJSON(for: patientID, action: "api/goals/SavePatientGoal", body: [
            "key": 0,
            "goal": ["lastUpdatedDate": formatter.string(from: .now), "text": text]
        ], savesCopy: false)
        // The reply hasn't been captured, so only an explicit failure counts.
        let reply = json as? [String: Any] ?? [:]
        if reply["isSuccess"] as? Bool == false || !(reply["errors"] as? [Any] ?? []).isEmpty {
            throw MyChartError.actionFailed("SavePatientGoal")
        }
    }

    /// Captured from Home's "Explore More" panel: an empty POST (legacy
    /// style, `noCache` in the query). Answers `{Title, ExploreMoreItems[]}`;
    /// each item has TitleDisplayText, BodyDisplayText, IconKey (an image URL,
    /// or a keyword like "announcements_information"), and primary/secondary
    /// link text and URIs. `Subjects` maps each child to their own title.
    func exploreMore(for patientID: String) async throws -> ExploreMoreFeed {
        let json = try await postLegacy(for: patientID, path: "ExploreMoreFeed", query: [:])
        guard let root = json as? [String: Any] else { return ExploreMoreFeed(title: "Explore More", items: []) }
        func link(_ item: [String: Any], _ text: String, _ uri: String) -> (title: String, url: URL)? {
            guard let title = Self.string(item, text), let url = Self.string(item, uri).flatMap(URL.init(string:)),
                  url.scheme == "https" || url.scheme == "http" else { return nil }
            return (title, url)
        }
        let items = (root["ExploreMoreItems"] as? [[String: Any]] ?? []).enumerated().compactMap { index, item -> ExploreItem? in
            guard let title = Self.string(item, "TitleDisplayText") else { return nil }
            let icon = Self.string(item, "IconKey").flatMap { key -> URL? in
                if key.hasPrefix("https://") { return URL(string: key) }
                if key.hasPrefix("/") { return URL(string: "https://\(config.host)\(key)") }
                return nil
            }
            return ExploreItem(id: Self.string(item, "EncryptedCctId") ?? "explore-\(index)",
                               title: title,
                               body: Self.string(item, "BodyDisplayText") ?? "",
                               iconURL: icon,
                               primary: link(item, "PrimaryUriDisplayText", "PrimaryUri"),
                               secondary: link(item, "SecondaryUriDisplayText", "SecondaryUri"))
        }
        return ExploreMoreFeed(title: Self.string(root, "Title") ?? "Explore More", items: items)
    }

    /// Captured from the site's immunisation-details page. `id` is the vaccine
    /// record's id from LoadImmunizations; the site sends name and orgId empty.
    func immunisationDoses(vaccineID: String, for patientID: String) async throws -> [ImmunisationDose] {
        let json = try await postJSON(for: patientID, action: "api/immunization-details/GetImmunizationDetails",
                                      body: ["id": vaccineID, "name": "", "orgId": ""])
        let doses = (json as? [String: Any])?["immunizationDoses"] as? [[String: Any]] ?? []
        return doses.compactMap { item in
            // "2026-06-22": a date only, so read it as a Melbourne calendar day.
            guard let date = Self.string(item, "administeredDateISO").flatMap(Self.isoDay) else { return nil }
            // Staff type product names freely ("Vaxigrip", "vaxigrip").
            let product = Self.string(item, "productName").map { $0.prefix(1).uppercased() + $0.dropFirst() }
            return ImmunisationDose(
                date: date,
                productName: product,
                dose: Self.string(item, "dose"),
                route: Self.string(item, "route"),
                site: Self.string(item, "site"),
                location: Self.string(item, "location"),
                manufacturer: Self.string(item, "manufacturer"),
                lotNumber: Self.string(item, "lotNumber")
            )
        }
        .sorted { $0.date > $1.date }
    }

    private nonisolated static func isoDay(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Australia/Melbourne")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: text)
    }

    /// Prints cookie *names* only — values are session credentials.
    private func logCookies(_ label: String) {
        guard debugLogResponses else { return }
        let names = session.configuration.httpCookieStorage?.cookies(for: config.url(""))?.map(\.name) ?? []
        print("↩︎ Cookies \(label): \(names.sorted())")
    }

    /// `Home/CSRFToken` returns a bare `<input name=… value=…>` holding the
    /// token for the signed-in session. The site reads it as "first input's
    /// value" (`parseHtml(t).val()`), so don't depend on the input's name.
    private func fetchCSRFToken() async throws -> String? {
        var request = URLRequest(url: config.url("Home/CSRFToken"))
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        let (data, response) = try await session.data(for: request)
        let html = String(decoding: data, as: UTF8.self)
        let token = Self.firstInputValue(in: html)
        if debugLogResponses {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            // Only show the body's opening when no token was found, so a
            // working token never ends up in the console.
            let opening = token == nil ? ", starts \(html.prefix(60).replacingOccurrences(of: "\n", with: " "))…" : ""
            print("↩︎ CSRFToken: \(token == nil ? "not found" : "ok") — HTTP \(status) at \(response.url?.path ?? "?"), \(data.count) bytes\(opening)")
        }
        return token
    }

    /// Value of the first `<input>` in the fragment, if non-empty.
    nonisolated static func firstInputValue(in html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"<input\b[^>]*>"#, options: .caseInsensitive),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let r = Range(match.range, in: html),
              let value = attribute("value", in: String(html[r])), !value.isEmpty else { return nil }
        return value
    }

    /// Mirrors the site's `reconcileWebDevice`: the server issues a device ID
    /// that the browser keeps in localStorage and sends with future logins.
    /// Best effort — a failure here shouldn't block sign-in.
    private func reconcileDevice() async {
        let stored = Keychain.deviceID
        var request = URLRequest(url: config.url("Authentication/RememberDevices/ReconcileWebDevice"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let apiToken { request.setValue(apiToken, forHTTPHeaderField: "__RequestVerificationToken") }
        request.httpBody = Self.formEncode([
            "deviceId": stored ?? "",
            "skipSessionCheck": "false"
        ]).data(using: .utf8)

        guard let (data, _) = try? await session.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let issued = json["deviceId"] as? String, !issued.isEmpty else { return }
        let forceUpdate = json["forceUpdate"] as? Bool ?? false
        if forceUpdate || stored == nil { Keychain.deviceID = issued }
    }

    // MARK: - Transport

    /// jQuery-style `$.post`: form-encoded body, JSON response.
    private func postForm(_ path: String, fields: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: config.url(path))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/javascript, */*; q=0.01", forHTTPHeaderField: "Accept")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue("https://\(config.host)", forHTTPHeaderField: "Origin")
        request.setValue(config.url("Authentication/SecondaryValidation").absoluteString, forHTTPHeaderField: "Referer")
        if let apiToken { request.setValue(apiToken, forHTTPHeaderField: "__RequestVerificationToken") }
        request.httpBody = Self.formEncode(fields).data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        if debugLogResponses {
            // Log context flags, never the code itself.
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let logged = fields.filter { $0.key != "TwoFactorCode" }
            print("→ \(path): HTTP \(status) at \(response.url?.path ?? "?") sent \(logged)")
            print("↩︎ \(String(decoding: data, as: UTF8.self).prefix(500))")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MyChartError.decoding(action: path, snippet: String(decoding: data.prefix(300), as: UTF8.self))
        }
        return json
    }

    /// Legacy MVC actions (Visits and friends): parameters go in the query
    /// string, the body is form-encoded, and `noCache` defeats caching the way
    /// the site's own jQuery calls do.
    private func postLegacy(for patientID: String, path: String,
                            query: [String: String], form: [String: String] = [:]) async throws -> Any {
        // Saved copy first (if enabled in Settings), before any context switch.
        let diskKey = PortalDiskCache.shared.key(patientID: patientID, endpoint: path,
                                                 parameters: query.merging(form) { a, _ in a })
        if let saved = PortalDiskCache.shared.read(diskKey),
           let json = try? JSONSerialization.jsonObject(with: saved) {
            if debugLogResponses { print("→ \(path): from device cache") }
            return json
        }

        // Built per attempt, so a retry carries the refreshed token.
        func send() async throws -> (Data, URLResponse) {
            var components = URLComponents(url: config.url(path), resolvingAgainstBaseURL: false)!
            components.queryItems = (query.merging(["noCache": String(Double.random(in: 0..<1))]) { a, _ in a })
                .map { URLQueryItem(name: $0.key, value: $0.value) }

            var request = URLRequest(url: components.url!)
            request.httpMethod = "POST"
            request.setValue("application/json, text/javascript, */*; q=0.01", forHTTPHeaderField: "Accept")
            request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
            request.setValue("https://\(config.host)", forHTTPHeaderField: "Origin")
            request.setValue(config.url("Visits").absoluteString, forHTTPHeaderField: "Referer")
            if let apiToken { request.setValue(apiToken, forHTTPHeaderField: "__RequestVerificationToken") }
            if !form.isEmpty {
                request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
                request.httpBody = Self.formEncode(form).data(using: .utf8)
            }

            let (data, response) = try await session.data(for: request)
            if debugLogResponses {
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                print("→ \(path): HTTP \(status), \(data.count) bytes")
            }
            return (data, response)
        }

        await ensureContext(patientID)
        let generation = contextGeneration
        var (data, response) = try await send()
        // Once only: a second error page is reported as before.
        if Self.isErrorPage(response) {
            await recoverContext(patientID, seenGeneration: generation)
            (data, response) = try await send()
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) else {
            let text = String(decoding: data, as: UTF8.self)
            if debugLogResponses {
                // Page title only — enough to tell a login or error page apart.
                print("   not JSON (\(Self.pageTitle(in: text) ?? "no title")) at \(Self.landingDescription(response))")
            }
            if text.contains("Authentication/Login") { throw MyChartError.sessionExpired }
            throw MyChartError.decoding(action: path, snippet: String(text.prefix(200)))
        }
        PortalDiskCache.shared.write(data, for: diskKey)
        return json
    }

    /// POSTs an empty JSON body to an api/ action and returns parsed JSON.
    /// `savesCopy: false` for actions that change something on the portal,
    /// which must always reach it and whose replies aren't worth keeping.
    /// `referer` overrides the page sent as Referer (default: health summary).
    private func postJSON(for patientID: String, action: String, body: [String: Any] = [:],
                          savesCopy: Bool = true, referer: String? = nil) async throws -> Any {
        // Saved copy first (if enabled in Settings), before any context switch.
        let diskKey = PortalDiskCache.shared.key(patientID: patientID, endpoint: action, parameters: body)
        if savesCopy, let saved = PortalDiskCache.shared.read(diskKey),
           let json = try? JSONSerialization.jsonObject(with: saved) {
            if debugLogResponses { print("→ \(action): from device cache") }
            return json
        }

        let httpBody = try JSONSerialization.data(withJSONObject: body)
        // Built per attempt, so a retry carries the refreshed token.
        func send() async throws -> (Data, URLResponse) {
            var request = URLRequest(url: config.url(action))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            // Match Safari's captured api/ requests: the React client sends Origin
            // and the app page as Referer, and no X-Requested-With.
            request.setValue("https://\(config.host)", forHTTPHeaderField: "Origin")
            request.setValue(referer ?? config.url("app/health-summary").absoluteString, forHTTPHeaderField: "Referer")
            if let apiToken { request.setValue(apiToken, forHTTPHeaderField: "__RequestVerificationToken") }
            request.httpBody = httpBody

            let (data, response) = try await session.data(for: request)
            if debugLogResponses {
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                print("→ \(action): HTTP \(status) at \(Self.landingDescription(response))")
                if status >= 500, let http = response as? HTTPURLResponse {
                    // Epic sometimes explains a failure in headers rather than the body.
                    let headers = http.allHeaderFields
                        .map { "\($0.key): \($0.value)" }
                        .filter { !$0.lowercased().hasPrefix("set-cookie") && !$0.lowercased().hasPrefix("content-security-policy") }
                        .sorted()
                    print("   headers: \(headers)")
                }
            }
            return (data, response)
        }

        await ensureContext(patientID)
        let generation = contextGeneration
        var (data, response) = try await send()
        // Once only: a second error page is reported as before. Reads only:
        // an action that changes something (e.g. sending a reply) might have
        // run before the redirect, so it isn't repeated.
        if Self.isErrorPage(response) {
            await recoverContext(patientID, seenGeneration: generation)
            if savesCopy { (data, response) = try await send() }
        }

        // Session expiry returns 200 with login-page HTML rather than JSON.
        if let text = String(data: data, encoding: .utf8),
           text.contains("Authentication/Login") || text.hasPrefix("<") {
            throw MyChartError.sessionExpired
        }
        // Fragments allowed: SendReply answers with a bare JSON string.
        let json = try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
        // Only valid JSON reaches here, so error pages are never saved.
        if savesCopy { PortalDiskCache.shared.write(data, for: diskKey) }
        return json
    }

    // MARK: - Decoding (best-effort — verify against live JSON)

    /// LoadUpcoming splits visits across InProgressVisits / NextNDaysVisits /
    /// LaterVisitsList; LoadPast nests them somewhere under `List`. Rather than
    /// hard-code either layout, collect every dictionary that looks like a visit.
    private func decodeAppointments(_ json: Any?, status: Appointment.Status) -> [Appointment] {
        guard let json else { return [] }
        var visits: [[String: Any]] = []
        Self.collectVisits(in: json, into: &visits)

        var seen = Set<String>()
        var undated = 0
        let appointments = visits.enumerated().compactMap { index, visit -> Appointment? in
            let id = Self.string(visit, "Csn", "Id") ?? "visit-\(status)-\(index)"
            // A visit can appear in more than one upcoming bucket.
            guard seen.insert(id).inserted else { return nil }
            guard let date = Self.visitDate(visit) else { undated += 1; return nil }

            let department = visit["PrimaryDepartment"]
            let departmentInfo = department as? [String: Any] ?? [:]
            let resolvedStatus: Appointment.Status =
                visit["IsCanceled"] as? Bool == true ? .cancelled
                : (visit["IsNoShow"] as? Bool == true || visit["LeftWithoutSeen"] as? Bool == true) ? .missed
                : status

            return Appointment(
                id: id,
                title: Self.string(visit, "VisitTypeName") ?? "Appointment",
                department: (department as? String)
                    ?? Self.string(departmentInfo, "Name", "DisplayName") ?? "",
                provider: Self.string(visit, "PrimaryProviderName")
                    ?? Self.string(visit["PrimaryProvider"] as? [String: Any] ?? [:], "Name"),
                date: date,
                status: resolvedStatus,
                // TelehealthMode is 0 for in-person visits.
                isTelehealth: visit["CanShowTelemedicine"] as? Bool == true
                    || visit["IsUnverifiedOnDemandVideoVisit"] as? Bool == true
                    || (Self.int(visit, "TelehealthMode") ?? 0) != 0,
                hasVisitSummary: visit["IsVisitSummaryEnabled"] as? Bool == true
                    || visit["HasDownloadSummaryLink"] as? Bool == true,
                // Past visits send null here.
                durationMinutes: Self.int(visit, "DurationInMinutes").flatMap { $0 > 0 ? $0 : nil } ?? 30,
                address: Self.address(departmentInfo),
                // The portal wraps phone numbers in bidi embedding marks (U+202A…U+202C).
                phone: Self.string(departmentInfo, "PhoneNumber")?
                    .filter { !("\u{202A}"..."\u{202E}").contains($0) },
                checkInLocation: Self.string(departmentInfo, "ArrivalLocation"),
                instructions: Self.visitInstructions(visit, department: departmentInfo)
            )
        }

        if debugLogResponses {
            print("↩︎ visits (\(status)): found \(visits.count), decoded \(appointments.count), no date \(undated)")
            if visits.isEmpty, let dict = json as? [String: Any] {
                // Nothing matched — show where the list might be hiding (keys only).
                let nested = dict.compactMap { key, value -> String? in
                    if let inner = value as? [String: Any] { return "\(key){\(inner.keys.sorted().joined(separator: ","))}" }
                    if let array = value as? [Any] { return "\(key)[\(array.count)]" }
                    return nil
                }
                print("   top-level keys \(dict.keys.sorted()), containers \(nested.sorted())")
            }
        }
        return appointments
    }

    /// Next-step text for the visit plus any department instructions the
    /// portal has flagged for display.
    private nonisolated static func visitInstructions(_ visit: [String: Any], department: [String: Any]) -> [String] {
        var lines = string(visit, "PatientNextStepInstructions").map { [$0] } ?? []
        if department["ShouldShowInstructions"] as? Bool == true {
            let items = department["Instructions"] as? [Any] ?? []
            lines += items.compactMap { item in
                (item as? String) ?? string(item as? [String: Any] ?? [:], "Text", "Instruction", "Value")
            }
        }
        return lines.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// Depth-first search for visit dictionaries (they all carry VisitTypeName).
    private nonisolated static func collectVisits(in json: Any, into visits: inout [[String: Any]]) {
        if let dict = json as? [String: Any] {
            // Some visits (e.g. non-Epic or admissions) omit Csn, so accept
            // any dictionary with a visit type and a date.
            let hasDate = dict["Instant"] != nil || dict["PrimaryDate"] != nil || dict["Date"] is String
            if hasDate, dict["VisitTypeName"] != nil || dict["Csn"] != nil {
                visits.append(dict)
                return
            }
            for key in dict.keys.sorted() { collectVisits(in: dict[key]!, into: &visits) }
        } else if let array = json as? [Any] {
            for item in array { collectVisits(in: item, into: &visits) }
        }
    }

    /// Visit start time. `Instant` is the most precise when present; otherwise
    /// combine the display `Date` and `Time` strings.
    private nonisolated static func visitDate(_ visit: [String: Any]) -> Date? {
        for key in ["Instant", "PrimaryDate", "Dat"] {
            if let text = visit[key] as? String, let date = epicDate(text) { return date }
        }
        guard let day = string(visit, "Date") else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_AU")
        let time = string(visit, "Time")
        let dayFormats = ["d/MM/yyyy", "dd/MM/yyyy", "EEEE d MMMM yyyy", "EEEE, d MMMM yyyy",
                          "d MMMM yyyy", "d MMMM, yyyy", "MMMM d, yyyy", "yyyy-MM-dd"]
        let timeFormats = ["h:mm a", "h:mma", "HH:mm"]
        for dayFormat in dayFormats {
            if let time {
                for timeFormat in timeFormats {
                    formatter.dateFormat = "\(dayFormat) \(timeFormat)"
                    if let date = formatter.date(from: "\(day) \(time)") { return date }
                }
            }
            formatter.dateFormat = dayFormat
            if let date = formatter.date(from: day) { return date }
        }
        return nil
    }

    /// Epic sends machine dates as ISO-8601 or ASP.NET's `/Date(1717200000000)/`.
    private nonisolated static func epicDate(_ text: String) -> Date? {
        if text.hasPrefix("/Date("),
           let ms = Double(text.dropFirst(6).prefix { $0.isNumber || $0 == "-" }) {
            return Date(timeIntervalSince1970: ms / 1000)
        }
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: text) { return date }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: text) { return date }
        // Local time without a zone, e.g. 2026-10-02T09:30:00
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter.date(from: String(text.prefix(19)))
    }

    private nonisolated static func address(_ department: [String: Any]) -> String? {
        if let lines = department["Address"] as? [String], !lines.isEmpty {
            return lines.joined(separator: ", ")
        }
        return string(department, "Address", "AddressString")
    }
    /// `GetList` returns results as a dictionary, `newResults`, keyed by
    /// "<key>^". The list call leaves `resultComponents` empty
    /// (`hasAllDetails: false`), so values and ranges need a separate detail call.
    private func decodeTestResults(_ json: Any) -> [TestResult] {
        let results = (json as? [String: Any])?["newResults"] as? [String: [String: Any]] ?? [:]
        return results.compactMap { dictKey, item in
            let metadata = item["orderMetadata"] as? [String: Any] ?? [:]
            guard let date = Self.string(metadata, "prioritizedInstantISO")
                .flatMap(ISO8601DateFormatter().date(from:)) else { return nil }
            let kind: TestResult.Kind = switch Self.string(metadata, "resultType") {
            case "IMAGING": .imaging
            case "PATHOLOGY": .pathology
            default: .lab
            }
            return TestResult(
                id: Self.string(item, "key") ?? dictKey,
                // Names arrive upper-case ("FULL BLOOD COUNT").
                name: Self.string(item, "name")?.capitalized ?? "Test result",
                date: date,
                kind: kind,
                orderingProvider: Self.string(metadata, "authorizingProviderName", "orderProviderName") ?? "",
                // Seen as "Read"; treat any other value as unread.
                isUnread: Self.string(metadata, "read").map { $0 != "Read" } ?? false,
                summary: nil,
                isFlaggedAbnormal: item["isAbnormal"] as? Bool ?? false
            )
        }
    }
    /// `GetDetails` wraps the order in `results[]` (one entry per result on the
    /// order), each with `resultComponents[]` holding the values and ranges.
    /// Imaging has no components; its report is under `studyResult`.
    private func decodeTestResultDetails(_ json: Any, into result: TestResult) -> TestResult {
        let items = (json as? [String: Any])?["results"] as? [[String: Any]] ?? []
        guard !items.isEmpty else { return result }
        var detailed = result

        let components = items.flatMap { $0["resultComponents"] as? [[String: Any]] ?? [] }
        detailed.components = components.enumerated().map { index, item in
            Self.decodeComponent(item, index: index, resultID: result.id)
        }
        if debugLogResponses {
            // Flag categories only, no names or values: confirms which strings
            // mean "abnormal".
            let flags = Set(components.compactMap {
                ($0["componentResultInfo"] as? [String: Any])?["abnormalFlagCategoryValue"] as? String
            })
            print("   abnormal flag categories: \(flags.sorted())")
        }

        let item = items[0]
        let metadata = item["orderMetadata"] as? [String: Any] ?? [:]
        detailed.isFlaggedAbnormal = items.contains { $0["isAbnormal"] as? Bool ?? false }
        detailed.status = Self.string(metadata, "resultStatus") ?? detailed.status
        detailed.specimen = Self.string(metadata, "specimensDisplay")
        detailed.authorisingClinician = Self.string(metadata, "readingProviderName")
        if detailed.orderingProvider.isEmpty {
            detailed.orderingProvider = Self.string(metadata, "orderProviderName", "authorizingProviderName") ?? ""
        }
        // e.g. "05 Feb, 2026 8:04 AM". latestUpdateInstantISO has no zone
        // ("2026-02-05T13:53:28"), so the display string is more reliable.
        detailed.resultDate = Self.portalTimestamp(Self.string(metadata, "resultTimestampDisplay"))
        if let lab = metadata["resultingLab"] as? [String: Any], let name = Self.string(lab, "name") {
            let address = (lab["address"] as? [String] ?? []).filter { !$0.isEmpty }
            detailed.resultingLab = ([name] + address).joined(separator: "\n")
        }

        // Written report. Imaging splits it into narrative (findings) and
        // impression (conclusion), which the combined section merges; keep
        // both rather than just the conclusion. Otherwise use any note or
        // letter on the result.
        let study = item["studyResult"] as? [String: Any] ?? [:]
        let findings = Self.reportText(study["narrative"])
        let impression = Self.reportText(study["impression"])
        let split = [findings, impression.map { "Impression: \($0)" }].compactMap { $0 }
        detailed.summary = Self.reportText(study["combinedRTFNarrativeImpression"])
            ?? (split.isEmpty ? nil : split.joined(separator: "\n\n"))
            ?? Self.reportText(item["resultNote"])
            ?? Self.reportText(item["resultLetter"])
            ?? result.summary

        detailed.comments = items.flatMap { $0["providerComments"] as? [[String: Any]] ?? [] }
            .enumerated()
            .compactMap { index, comment in
                let content = comment["content"] as? [String: Any] ?? [:]
                guard let body = Self.string(content, "body")?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !body.isEmpty else { return nil }
                return ResultComment(
                    id: Self.string(content, "wmgId") ?? "\(result.id)-comment-\(index)",
                    author: Self.string(comment["author"] as? [String: Any] ?? [:], "name") ?? "Care team",
                    date: Self.string(content, "deliveryInstantISO").flatMap(ISO8601DateFormatter().date(from:)),
                    text: body
                )
            }

        // Attached scans are links like
        // "/Clinical/TestResults/BlobScans/BlobScansDownloadOrStream?…&displayName=Scan%20-%20…",
        // relative to the portal's base path.
        let links = items.flatMap { item in
            ["imageStudies", "scans"].flatMap { item[$0] as? [[String: Any]] ?? [] }
        }
        .compactMap { Self.string($0, "downloadUrl") }
        detailed.documents = links.enumerated().map { index, path in
            ResultDocument(id: path, title: Self.documentTitle(path, index: index, count: links.count),
                           pageCount: nil, downloadPath: path)
        }
        if detailed.documents.isEmpty { detailed.documents = result.documents }
        return detailed
    }

    /// "Scan" from displayName "Scan - PANCREATIC ELASTASE - 22 Dec, 2025";
    /// the rest repeats the test name and date shown above it.
    private nonisolated static func documentTitle(_ path: String, index: Int, count: Int) -> String {
        let displayName = URLComponents(string: path)?.queryItems?
            .first { $0.name == "displayName" }?.value
        let title = displayName?.components(separatedBy: " - ").first ?? "Document"
        return count > 1 ? "\(title) \(index + 1)" : title
    }

    /// Portal timestamps, e.g. "05 Feb, 2026 8:04 AM", in the hospital's zone.
    private nonisolated static func portalTimestamp(_ text: String?) -> Date? {
        guard let text else { return nil }
        let formatter = DateFormatter()
        // POSIX so "AM"/"PM" parse regardless of the device's locale.
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Australia/Melbourne")
        for format in ["dd MMM, yyyy h:mm a", "d MMM, yyyy h:mm a"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }

    private nonisolated static func decodeComponent(_ item: [String: Any], index: Int, resultID: String) -> ResultComponent {
        let info = item["componentInfo"] as? [String: Any] ?? [:]
        let resultInfo = item["componentResultInfo"] as? [String: Any] ?? [:]
        let range = resultInfo["referenceRange"] as? [String: Any] ?? [:]
        // Text values arrive with Windows line endings and a trailing newline.
        let rawValue = string(resultInfo, "value")?
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let plain = rawValue.flatMap(number)
        // ">500" or "<1": plot at the bound, but keep the text as written.
        let censored = plain == nil ? rawValue.flatMap(censoredNumber) : nil
        let value = plain ?? censored?.value
        let flag = string(resultInfo, "abnormalFlagCategoryValue")?.lowercased() ?? ""

        // One-sided ranges (">200", "<5") only come as text, with
        // displayLow/displayHigh empty.
        let rangeText = string(range, "formattedReferenceRange")
        let parsedRange: (low: Double?, high: Double?) = rangeText.map(referenceRange) ?? (nil, nil)
        return ResultComponent(
            // componentID isn't unique: each organism in a culture repeats the
            // "Culture" component's ID, so the position is part of the id.
            id: "\(resultID)-\(index)-\(string(info, "componentID") ?? "")",
            // "Gram stain description" → "Gram Stain Description".
            name: titleCased(string(info, "name", "commonName") ?? "Result"),
            value: value,
            unit: string(info, "units") ?? "",
            normalLow: string(range, "displayLow").flatMap(number) ?? parsedRange.low,
            normalHigh: string(range, "displayHigh").flatMap(number) ?? parsedRange.high,
            // Show the portal's text for anything that isn't a plain number.
            valueText: plain == nil ? rawValue : nil,
            rangeText: rangeText,
            // "Unknown" is seen on in-range values, so it isn't a flag. Other
            // values (High, Low…) are assumed to be; unconfirmed so far.
            isFlaggedAbnormal: !flag.isEmpty && !["unknown", "normal", "none", "not abnormal"].contains(flag),
            qualifier: censored?.qualifier
        )
    }

    /// Parses "4.5" or "1,200"; rejects qualified values such as "<5".
    private nonisolated static func number(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces))
    }

    /// "<1", "<= 1", "≤1" → (1, lessThan); ">500", "≥500" → (500, greaterThan).
    private nonisolated static func censoredNumber(_ text: String) -> (value: Double, qualifier: ResultComponent.Qualifier)? {
        let text = text.trimmingCharacters(in: .whitespaces)
        for (prefix, qualifier) in [("<=", ResultComponent.Qualifier.lessThan), ("≤", .lessThan), ("<", .lessThan),
                                    (">=", .greaterThan), ("≥", .greaterThan), (">", .greaterThan)] {
            if text.hasPrefix(prefix), let value = number(String(text.dropFirst(prefix.count))) {
                return (value, qualifier)
            }
        }
        return nil
    }

    /// Reference range text → bounds: "<5" (upper only), ">200" (lower only),
    /// "3.5-5.0" / "3.5 – 5.0" (both). Anything else gives no bounds.
    private nonisolated static func referenceRange(_ text: String) -> (low: Double?, high: Double?) {
        if let (bound, qualifier) = censoredNumber(text) {
            return qualifier == .lessThan ? (nil, bound) : (bound, nil)
        }
        let parts = text.components(separatedBy: CharacterSet(charactersIn: "-–—"))
        if parts.count == 2, let low = number(parts[0]), let high = number(parts[1]), low < high {
            return (low, high)
        }
        return (nil, nil)
    }

    /// Text of a `{hasContent, contentAsString, contentAsHtml}` block. Falls
    /// back to the HTML with tags stripped, since RTF-sourced reports may
    /// only fill that field.
    private nonisolated static func reportText(_ block: Any?) -> String? {
        guard let block = block as? [String: Any], block["hasContent"] as? Bool ?? false else { return nil }
        var text = string(block, "contentAsString")
        if text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true,
           let html = string(block, "contentAsHtml") {
            text = plainText(fromHTML: html)
        }
        let trimmed = text?
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    /// Report HTML to plain text: one line per paragraph/row, blank
    /// paragraphs (`&nbsp;`) kept as single blank lines between sections.
    /// Also used to give documents' text to the on-device model.
    nonisolated static func plainText(fromHTML html: String) -> String {
        let text = html
            .replacingOccurrences(of: "\r\n", with: "\n")
            // Markup-only content: embedded CSS and comments.
            .replacingOccurrences(of: #"<style[^>]*>[\s\S]*?</style>"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"<!--[\s\S]*?-->"#, with: "", options: .regularExpression)
            // Source newlines are just formatting; structure comes from tags.
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: #"<br\s*/?>|</p>|</div>|</tr>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
        // Trim each line and collapse runs of blank lines to one.
        var lines: [String] = []
        for line in text.components(separatedBy: "\n").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            if line.isEmpty, lines.last?.isEmpty ?? true { continue }
            lines.append(line)
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Prints the key structure of a response with every value replaced by
    /// its type, so the shape can be read from the console without leaking
    /// any health data. Arrays show their first element only.
    private nonisolated static func logShape(_ json: Any, label: String) {
        func shape(_ value: Any, indent: String) -> String {
            switch value {
            case let dict as [String: Any]:
                guard !dict.isEmpty else { return "{}" }
                let inner = indent + "  "
                let lines = dict.keys.sorted().map { "\(inner)\($0): \(shape(dict[$0]!, indent: inner))" }
                return "{\n" + lines.joined(separator: "\n") + "\n\(indent)}"
            case let array as [Any]:
                guard let first = array.first else { return "[]" }
                return "[\(array.count)× " + shape(first, indent: indent) + "]"
            case is String: return "String"
            case let number as NSNumber:
                // Booleans are printed: flags like hasContent carry no health
                // data and show which sections are actually filled in.
                return CFGetTypeID(number) == CFBooleanGetTypeID() ? "Bool(\(number.boolValue))" : "Number"
            case is NSNull: return "null"
            default: return "\(type(of: value))"
            }
        }
        print("↩︎ \(label) shape:\n\(shape(json, indent: ""))")
    }

    /// `LoadMedicationsPage` nests the list under one entry per organisation:
    /// communityMembers[].prescriptionList.prescriptions[].
    private func decodeMedications(_ json: Any) -> [Medication] {
        let members = (json as? [String: Any])?["communityMembers"] as? [[String: Any]] ?? []
        let prescriptions = members.flatMap { member -> [[String: Any]] in
            let list = member["prescriptionList"] as? [String: Any]
            return list?["prescriptions"] as? [[String: Any]] ?? []
        }
        return prescriptions.enumerated().map { index, item in
            let name = Self.medicationName(Self.string(item, "name") ?? "Unknown medicine")
            // patientFriendlyName is the plain-language name, e.g. "Hypersal";
            // only useful when it differs from the prescription name. The
            // live portal sends it as {caption, captionType, text}; a plain
            // string is still accepted.
            let friendly = (item["patientFriendlyName"] as? [String: Any]).flatMap { Self.string($0, "text") }
                ?? Self.string(item, "patientFriendlyName")
            let provider = (item["authorizingProvider"] as? [String: Any])
                ?? (item["orderingProvider"] as? [String: Any])
            let refill = item["refillDetails"] as? [String: Any] ?? [:]
            // The portal gives one name holding strength and form; split
            // them out. Ones the family added follow the Add Medication
            // screen's format; prescriptions follow the pharmacy's.
            // A live proxy account showed `isPatientReported` false on
            // everything; the family's additions were the only ones with
            // `isClinicReported` false (and `isPendingUpdate` and
            // `showPendingUndoAddButton` true, awaiting review).
            let isPatientReported = item["isPatientReported"] as? Bool == true
                || item["isClinicReported"] as? Bool == false
            let parts = isPatientReported ? Medication.splitReportedName(name) : Medication.splitPrescriptionName(name)
            return Medication(
                id: Self.string(item, "id") ?? Self.string(item, "prescriptionNumber") ?? "med-\(index)",
                name: parts.name,
                // Epic keeps dose inside the sig rather than a separate field.
                dose: parts.strength ?? "",
                instructions: Self.string(item, "sig") ?? "",
                prescriber: Self.string(provider ?? [:], "name") ?? "",
                // These come from the current-medications list, so treat them
                // as active unless the portal flags a pending removal.
                isActive: !(item["showPendingUndoDeleteButton"] as? Bool ?? false),
                commonName: friendly.flatMap { friendly in
                    [name, parts.name, Self.string(item, "name") ?? ""]
                        .contains { $0.caseInsensitiveCompare(friendly) == .orderedSame } ? nil : friendly
                },
                form: Self.medicationForm(name: name, sig: Self.string(item, "sig")),
                prescribedDate: Self.portalDate(Self.string(item, "startDate"))
                    ?? Self.portalDate(Self.string(item, "dateToDisplay")),
                quantity: Self.dispenseQuantity(refill),
                daySupply: Self.int(refill, "daySupply"),
                canRequestRepeat: item["showRefillButton"] as? Bool ?? false,
                isPatientReported: isPatientReported,
                productForm: parts.form,
                sourceName: name,
                portalName: Self.string(item, "name"),
                updateReferenceID: Self.string(item["updateInformation"] as? [String: Any] ?? [:], "referenceID")
            )
        }
    }

    /// "sodium chloride 6 % solution" → "Sodium Chloride 6% Solution".
    /// Units after a number keep their case ("400 mg/5 mL", not "Mg/5 ML"),
    /// and short joining words stay lower-case ("Water for Injection").
    nonisolated static func medicationName(_ raw: String) -> String {
        let joined = raw.replacingOccurrences(of: #"(\d)\s+%"#, with: "$1%", options: .regularExpression)
        let minor: Set<String> = ["and", "for", "in", "of", "with", "to", "or", "per"]
        var words: [String] = []
        for (index, word) in joined.split(separator: " ").enumerated() {
            let followsNumber = words.last?.last?.isNumber ?? false
            let isMinor = index > 0 && minor.contains(word.lowercased())
            if followsNumber || isMinor || !(word.first?.isLetter ?? false) {
                words.append(String(word))
            } else {
                words.append(word.prefix(1).uppercased() + word.dropFirst())
            }
        }
        return words.joined(separator: " ")
    }

    /// The response carries no form field, so infer it from the prescription
    /// name and instructions ("Inhale 2 puffs…", "…oral liquid").
    nonisolated static func medicationForm(name: String, sig: String?) -> Medication.Form {
        let text = "\(name) \(sig ?? "")".lowercased()
        return switch true {
        case text.contains("capsule"): .capsule
        case text.contains("inhal"), text.contains("puff"), text.contains("nebul"): .inhaled
        case text.contains("inject"), text.contains("subcut"), text.contains("syringe"): .injection
        case text.contains("cream"), text.contains("ointment"), text.contains("apply"): .topical
        case text.contains("liquid"), text.contains("syrup"), text.contains("suspension"),
             text.contains("solution"), text.contains("drops"), text.contains("nebule"): .liquid
        default: .tablet
        }
    }

    /// e.g. "100 sachets" from writtenDispenseQuantity + writtenDispenseUnit.
    private nonisolated static func dispenseQuantity(_ refill: [String: Any]) -> String? {
        let amount = string(refill, "writtenDispenseQuantity", "writtenDispenseAmount")
            ?? int(refill, "writtenDispenseQuantity", "writtenDispenseAmount").map(String.init)
        guard let amount, !amount.isEmpty else { return nil }
        guard let unit = string(refill, "writtenDispenseUnit") else { return amount }
        return "\(amount) \(unit)"
    }

    /// Numbers arrive as Int, Double or String depending on the field.
    private nonisolated static func int(_ dict: [String: Any], _ keys: String...) -> Int? {
        for key in keys {
            if let value = dict[key] as? Int { return value }
            if let value = dict[key] as? Double { return Int(value) }
            if let value = dict[key] as? String, let value = Int(value) { return value }
        }
        return nil
    }

    /// First non-empty string among `keys`.
    private nonisolated static func string(_ dict: [String: Any], _ keys: String...) -> String? {
        for key in keys {
            if let value = dict[key] as? String, !value.isEmpty { return value }
        }
        return nil
    }

    /// Portal display dates, e.g. "12 August, 2026".
    private nonisolated static func portalDate(_ text: String?) -> Date? {
        guard let text else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_AU")
        for format in ["d MMMM, yyyy", "d MMMM yyyy", "dd/MM/yyyy", "yyyy-MM-dd"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        // startDate may be ISO-8601 rather than a display string.
        return ISO8601DateFormatter().date(from: text)
    }
    /// Who's who in a conversation response: `users` (care team, keyed by
    /// empKey, sometimes prefixed "ser_"), `viewers` (the family, keyed by
    /// wprKey, with `isSelf` for the signed-in account), and
    /// `userOverrideNames` for display names.
    private struct ConversationPeople {
        var staff: [String: String] = [:]
        var family: [String: (name: String, isSelf: Bool, wprID: String?)] = [:]

        func staffName(_ key: String) -> String? { staff[key] ?? staff["ser_\(key)"] }
    }

    private nonisolated static func conversationPeople(_ root: [String: Any]) -> ConversationPeople {
        var people = ConversationPeople()
        for (key, user) in root["users"] as? [String: [String: Any]] ?? [:] {
            if let name = string(user, "name") { people.staff[key] = name }
        }
        for (key, viewer) in root["viewers"] as? [String: [String: Any]] ?? [:] {
            people.family[key] = (string(viewer, "name") ?? "Family", viewer["isSelf"] as? Bool ?? false,
                                  string(viewer, "wprId"))
        }
        return people
    }

    /// One conversation, from the list (`conversations[]`) or the details
    /// response (the root itself). Messages come oldest first; a care-team
    /// author has `author.empKey`, a family author `author.wprKey`. Bodies
    /// are HTML with CRLF line endings.
    private nonisolated static func decodeConversation(_ item: [String: Any], people: ConversationPeople) -> Conversation? {
        guard let id = string(item, "hthId") else { return nil }
        var overrides = people
        for (key, name) in item["userOverrideNames"] as? [String: String] ?? [:] where !name.isEmpty {
            overrides.staff[key] = name
        }
        let messages = (item["messages"] as? [[String: Any]] ?? []).compactMap { message -> ConversationMessage? in
            guard let messageID = string(message, "wmgId"),
                  let date = string(message, "deliveryInstantISO").flatMap(ISO8601DateFormatter().date(from:)) else { return nil }
            let author = message["author"] as? [String: Any] ?? [:]
            let family = string(author, "wprKey").flatMap { overrides.family[$0] }
            let staffName = string(author, "empKey").flatMap(overrides.staffName)
            return ConversationMessage(
                id: messageID,
                authorName: string(author, "displayName") ?? family?.name ?? staffName ?? "Care team",
                authorRole: nil,
                isFromMe: family?.isSelf ?? false,
                date: date,
                body: plainText(fromHTML: string(message, "body") ?? ""))
        }
        .sorted { $0.date < $1.date }

        let participantKeys = item["userKeys"] as? [String] ?? []
        let participants = participantKeys.compactMap { key in
            overrides.staffName(key).map { CareTeamMember(id: key, name: $0, role: "", department: "") }
        }
        return Conversation(
            id: id,
            subject: string(item, "subject") ?? "Message",
            participants: participants,
            messages: messages,
            isUnread: (item["messages"] as? [[String: Any]] ?? []).contains { $0["isUnread"] as? Bool ?? false },
            // `tags` is like {"Messages": true, "Bookmark": true}.
            isBookmarked: (item["tags"] as? [String: Any])?["Bookmark"] as? Bool ?? false,
            lastViewedByStaff: string(item, "lastViewedByStaffInstantISO").flatMap(ISO8601DateFormatter().date(from:)),
            replyViewerID: people.family.values.first(where: \.isSelf)?.wprID,
            canReply: (item["replyFlags"] as? [String: Any])?["canReply"] as? Bool ?? true)
    }
    private func decodeCareTeam(_ json: Any) -> [CareTeamMember] { [] }
    /// `GetGrowthCharts`:
    /// - `datasetIDArray`: reference sets in the portal's order (first is the default)
    /// - `datasetDictionary[id].growthCharts[chartTypeId]`: axes and `curves[]`
    ///   (`label` like "50th percentile", `points[]` of xValue/yValue)
    /// - `patientData.measurementsInfo[chartTypeId].points[]`: the child's
    ///   measurements, shared by every set; `percentileMap[datasetID][i]` is
    ///   point i's percentile against that set, as a string ("42.17").
    private nonisolated static func decodeGrowth(_ json: Any) -> [GrowthDataset] {
        guard let root = json as? [String: Any],
              let sets = root["datasetDictionary"] as? [String: [String: Any]] else { return [] }
        let measurements = (root["patientData"] as? [String: Any])?["measurementsInfo"] as? [String: [String: Any]] ?? [:]
        let order = root["datasetIDArray"] as? [String] ?? Array(sets.keys)

        return order.compactMap { setID -> GrowthDataset? in
            guard let set = sets[setID] else { return nil }
            let charts = (set["growthCharts"] as? [String: [String: Any]] ?? [:])
                .sorted { (Int($0.key) ?? 0) < (Int($1.key) ?? 0) }
                .compactMap { chartID, chart in
                    decodeGrowthChart(chart, points: measurements[chartID], setID: setID, chartID: chartID)
                }
            return GrowthDataset(id: setID,
                                 name: growthSetName(string(set, "displayName") ?? "Growth chart"),
                                 source: string(set, "dataSource") ?? "",
                                 charts: charts)
        }
    }

    private nonisolated static func decodeGrowthChart(_ chart: [String: Any], points info: [String: Any]?,
                                                       setID: String, chartID: String) -> GrowthChart? {
        guard let kind = string(chart, "chartType") else { return nil }
        let xAxis = chart["xAxisInfo"] as? [String: Any] ?? [:]
        let yAxis = chart["yAxisInfo"] as? [String: Any] ?? [:]
        func range(_ axis: [String: Any]) -> ClosedRange<Double> {
            let low = axis["minVal"] as? Double ?? 0
            return low...max(low, axis["maxVal"] as? Double ?? low + 1)
        }
        let curves = (chart["curves"] as? [[String: Any]] ?? []).compactMap { curve -> GrowthCurve? in
            // "50th percentile"; the portal has typos like "3nd", so read the number.
            guard let label = string(curve, "label"),
                  let number = label.split(separator: " ").first.flatMap({ Double($0.filter(\.isNumber)) }) else { return nil }
            let points = (curve["points"] as? [[String: Any]] ?? []).compactMap { point -> GrowthCurve.Point? in
                guard let x = point["xValue"] as? Double, let y = point["yValue"] as? Double else { return nil }
                return .init(x: x, y: y)
            }
            return GrowthCurve(percentile: number, points: points)
        }
        .sorted { $0.percentile < $1.percentile }

        let raw = info?["points"] as? [[String: Any]] ?? []
        let percentiles = (info?["percentileMap"] as? [String: [String]])?[setID] ?? []
        let points = raw.enumerated().compactMap { index, point -> GrowthPoint? in
            guard let x = point["xValue"] as? Double, let y = point["yValue"] as? Double,
                  let date = string(point, "date").flatMap(shortMonthDate) else { return nil }
            let percentile = index < percentiles.count ? Double(percentiles[index]) : nil
            return GrowthPoint(id: "\(chartID)-\(index)", date: date, x: x, y: y, percentile: percentile)
        }
        .sorted { $0.date < $1.date }

        return GrowthChart(kind: kind, title: string(chart, "chartTypeName") ?? kind,
                           xLabel: string(xAxis, "label") ?? "", yLabel: string(yAxis, "label") ?? "",
                           xRange: range(xAxis), yRange: range(yAxis), curves: curves, points: points)
    }

    /// "WHO GIRLS (0-2 YEARS)" → "WHO Girls (0–2 years)".
    private nonisolated static func growthSetName(_ raw: String) -> String {
        var insideBrackets = false
        let words = raw.split(separator: " ").map { word -> String in
            if word.hasPrefix("(") { insideBrackets = true }
            defer { if word.hasSuffix(")") { insideBrackets = false } }
            if ["WHO", "CDC"].contains(word) { return String(word) }
            let lower = word.lowercased()
            return insideBrackets ? lower : lower.prefix(1).uppercased() + lower.dropFirst()
        }
        return words.joined(separator: " ")
            .replacingOccurrences(of: #"(\d)-(\d)"#, with: "$1–$2", options: .regularExpression)
    }
    /// `LoadHealthIssuesData` lists diagnoses under `dataList[]`, each with the
    /// merged `healthIssueItem` and the hospital's own `localItem`.
    private func decodeHealthIssues(_ json: Any) -> [HealthIssue] {
        let entries = (json as? [String: Any])?["dataList"] as? [[String: Any]] ?? []
        return entries.enumerated().compactMap { index, entry in
            guard let item = (entry["healthIssueItem"] ?? entry["localItem"]) as? [String: Any],
                  let name = Self.string(item, "name") else { return nil }
            return HealthIssue(
                id: Self.string(item, "id") ?? "issue-\(index)",
                name: Self.titleCased(name),
                // "16/12/2025"
                notedDate: Self.portalDate(Self.string(item, "formattedDateNoted"))
            )
        }
    }
    /// "Cystic fibrosis" → "Cystic Fibrosis". Raises only each word's first
    /// letter, so abbreviations ("COVID-19", "IgA") are left as written.
    private nonisolated static func titleCased(_ text: String) -> String {
        text.split(separator: " ", omittingEmptySubsequences: false)
            .map { word in word.prefix(1).uppercased() + word.dropFirst() }
            .joined(separator: " ")
    }

    private func decodeAllergies(_ json: Any) -> [Allergy] { [] }
    /// `LoadImmunizations` (body `{}`) groups by organisation:
    /// organizationImmunizationList[].orgImmunizations[], each vaccine with
    /// every dose date in `formattedAdministeredDates` ("22 Jun, 2026").
    /// Flattened to one Immunisation per dose; the views regroup by name.
    private func decodeImmunisations(_ json: Any) -> [Immunisation] {
        let organisations = (json as? [String: Any])?["organizationImmunizationList"] as? [[String: Any]] ?? []
        return organisations
            .flatMap { $0["orgImmunizations"] as? [[String: Any]] ?? [] }
            .flatMap { vaccine -> [Immunisation] in
                guard let name = Self.string(vaccine, "name") else { return [] }
                let id = Self.string(vaccine, "id") ?? name
                // "Influenza Trivalent (egg-based) >= 6 months" → "… ≥ 6 months".
                let displayName = name.replacingOccurrences(of: ">=", with: "≥")
                    .replacingOccurrences(of: "<=", with: "≤")
                let dates = (vaccine["formattedAdministeredDates"] as? [String] ?? []).compactMap(Self.shortMonthDate)
                return dates.map { date in
                    Immunisation(id: "\(id)|\(Int(date.timeIntervalSince1970))", name: displayName, date: date,
                                 vaccineID: Self.string(vaccine, "id"))
                }
            }
    }

    /// "22 Jun, 2026". POSIX, since en_AU's short months aren't all three
    /// letters ("Sept"), which would stop September dates parsing.
    private nonisolated static func shortMonthDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Australia/Melbourne")
        for format in ["dd MMM, yyyy", "d MMM, yyyy", "dd MMM yyyy"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }

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

    /// Inputs inside a single element with the given id (a `<form>` or
    /// `<div>`), so unrelated forms on the page don't leak in. Reads up to the
    /// element's first closing `</form>`/`</div>` — enough for the flat
    /// containers the portal uses (`actualLogin`, `__CSRFContainer`).
    nonisolated static func formInputs(in html: String, containerID: String) -> [String: String] {
        guard let start = html.range(of: "id=\"\(containerID)\"") ?? html.range(of: "id='\(containerID)'") else {
            return [:]
        }
        let rest = start.upperBound..<html.endIndex
        let closes = ["</form>", "</div>"].compactMap { html.range(of: $0, options: .caseInsensitive, range: rest) }
        guard let end = closes.min(by: { $0.lowerBound < $1.lowerBound }) else { return [:] }
        return formInputs(in: String(html[start.upperBound..<end.lowerBound]))
    }

    nonisolated static func extractToken(from html: String) -> String? {
        formInputs(in: html)["__RequestVerificationToken"].flatMap { $0.isEmpty ? nil : $0 }
    }

    nonisolated static func pageTitle(in html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"<title[^>]*>([^<]*)</title>"#, options: .caseInsensitive),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let r = Range(match.range(at: 1), in: html) else { return nil }
        return html[r].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Reads an attribute value, accepting either double or single quotes
    /// (the portal's hidden metrics inputs use single quotes).
    private nonisolated static func attribute(_ name: String, in tag: String) -> String? {
        let pattern = "\\b\(name)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)')"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)) else { return nil }
        for group in 1...2 {
            if let r = Range(match.range(at: group), in: tag) { return String(tag[r]) }
        }
        return nil
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
