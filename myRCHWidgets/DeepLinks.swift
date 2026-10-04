import Foundation

/// Links into the app (`myrch://…`), matching the app's `DeepLink` in
/// RootView.swift; keep the two in step. Every link can name the child, so
/// the app switches to them first.
enum DeepLink {
    private static func url(_ host: String, child: String?, _ items: [URLQueryItem] = []) -> URL? {
        var components = URLComponents(string: "myrch://\(host)")
        let all = items + (child.map { [URLQueryItem(name: "child", value: $0)] } ?? [])
        if !all.isEmpty { components?.queryItems = all }
        return components?.url
    }

    static func medicalIDURL(child: String?) -> URL? { url("medical-id", child: child) }

    static func doseURL(patientID: String, time: Date) -> URL? {
        url("dose", child: nil, [URLQueryItem(name: "patient", value: patientID),
                                 URLQueryItem(name: "time", value: String(time.timeIntervalSince1970))])
    }

    static func visitURL(child: String?, id: String?) -> URL? {
        url("visit", child: child, id.map { [URLQueryItem(name: "id", value: $0)] } ?? [])
    }

    static func visitsURL(child: String?) -> URL? { url("visits", child: child) }

    static func medicationURL(child: String?) -> URL? { url("medication", child: child) }

    static func whatsNewURL(child: String?) -> URL? { url("whats-new", child: child) }
}
