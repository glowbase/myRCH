import CryptoKit
import Foundation

/// Optional on-device copy of the portal's raw responses, so reopening the
/// app within five minutes doesn't refetch everything. Off unless turned on
/// in Settings, since it keeps health data on the phone.
///
/// Stored in Caches (which iOS may purge, and which isn't backed up), with
/// complete file protection, so the files are unreadable while the phone is
/// locked. Entries older than five minutes are ignored and replaced.
nonisolated final class PortalDiskCache: Sendable {
    static let shared = PortalDiskCache()

    static let enabledKey = "cachePortalDataOnDevice"
    static let lifetime: TimeInterval = 5 * 60

    /// Request fields that change on every call, so they're left out of the
    /// cache key (otherwise nothing would ever match).
    private static let volatileFields: Set<String> = ["PageNonce", "nonce", "noCache", "oldestRenderedDate"]

    private let folder: URL = URL.cachesDirectory.appending(path: "PortalResponses", directoryHint: .isDirectory)

    var isEnabled: Bool { UserDefaults.standard.bool(forKey: Self.enabledKey) }

    /// A stable key for a request: patient, endpoint, and its parameters
    /// minus the volatile ones.
    func key(patientID: String, endpoint: String, parameters: [String: Any]) -> String {
        let stable = parameters.filter { !Self.volatileFields.contains($0.key) }
        let encoded = (try? JSONSerialization.data(withJSONObject: stable, options: [.sortedKeys]))
            .map { String(decoding: $0, as: UTF8.self) } ?? ""
        return "\(patientID)|\(endpoint)|\(encoded)"
    }

    /// The saved response body, if caching is on and it's under five minutes old.
    func read(_ key: String) -> Data? {
        guard isEnabled else { return nil }
        let file = url(for: key)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
              let modified = attributes[.modificationDate] as? Date,
              Date.now.timeIntervalSince(modified) < Self.lifetime else { return nil }
        return try? Data(contentsOf: file)
    }

    func write(_ data: Data, for key: String) {
        guard isEnabled else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: url(for: key), options: [.atomic, .completeFileProtection])
    }

    /// Deletes one saved response, e.g. a list that a bookmark or move to
    /// trash has just changed.
    func remove(_ key: String) {
        try? FileManager.default.removeItem(at: url(for: key))
    }

    /// Deletes every saved response: on pull to refresh, sign-out, and when
    /// the setting is turned off.
    func removeAll() {
        try? FileManager.default.removeItem(at: folder)
    }

    /// File names are hashes, so no patient or record IDs appear on disk.
    private func url(for key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return folder.appending(path: digest + ".json")
    }
}
