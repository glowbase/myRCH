import Foundation

/// Links into the app (`myrch://…`), matching the app's `DeepLink` in
/// RootView.swift; keep the two in step.
enum DeepLink {
    static func medicalIDURL(child: String?) -> URL? {
        var components = URLComponents(string: "myrch://medical-id")
        if let child { components?.queryItems = [URLQueryItem(name: "child", value: child)] }
        return components?.url
    }

    static func doseURL(patientID: String, time: Date) -> URL? {
        var components = URLComponents(string: "myrch://dose")
        components?.queryItems = [URLQueryItem(name: "patient", value: patientID),
                                  URLQueryItem(name: "time", value: String(time.timeIntervalSince1970))]
        return components?.url
    }
}
