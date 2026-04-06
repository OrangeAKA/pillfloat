import Foundation

struct UpdateInfo {
    let version: String
    let releaseNotes: String
    let downloadURL: URL
    let publishDate: String
}

final class UpdateChecker {
    static let shared = UpdateChecker()

    private let repoOwner = "OrangeAKA"
    private let repoName = "pillfloat"
    private let lastCheckKey = "lastUpdateCheckDate"
    private let autoCheckKey = "autoCheckForUpdates"
    private let checkInterval: TimeInterval = 86400  // 24 hours

    var autoCheckEnabled: Bool {
        get {
            // Default to true if never set
            if UserDefaults.standard.object(forKey: autoCheckKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: autoCheckKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: autoCheckKey) }
    }

    /// The current app version from the bundle or hardcoded fallback.
    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    /// Cached latest update info (nil = no update or not checked yet).
    private(set) var latestUpdate: UpdateInfo?

    /// Called on app launch. Checks if enough time has passed since last auto-check.
    func checkIfNeeded(completion: @escaping (UpdateInfo?) -> Void) {
        guard autoCheckEnabled else {
            completion(nil)
            return
        }
        let lastCheck = UserDefaults.standard.double(forKey: lastCheckKey)
        let now = Date().timeIntervalSince1970
        if now - lastCheck < checkInterval {
            completion(latestUpdate)
            return
        }
        check(completion: completion)
    }

    /// Force a manual check regardless of timing.
    func check(completion: @escaping (UpdateInfo?) -> Void) {
        let urlString = "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest"
        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: self.lastCheckKey)

            guard let data = data, error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            let remoteVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName

            guard self.isNewerVersion(remoteVersion, than: self.currentVersion) else {
                self.latestUpdate = nil
                DispatchQueue.main.async { completion(nil) }
                return
            }

            let body = json["body"] as? String ?? ""
            let htmlURL = json["html_url"] as? String ?? ""
            let publishedAt = json["published_at"] as? String ?? ""

            let info = UpdateInfo(
                version: remoteVersion,
                releaseNotes: body,
                downloadURL: URL(string: htmlURL) ?? url,
                publishDate: publishedAt
            )
            self.latestUpdate = info
            DispatchQueue.main.async { completion(info) }
        }.resume()
    }

    /// Simple semantic version comparison (major.minor.patch).
    private func isNewerVersion(_ remote: String, than local: String) -> Bool {
        let remoteParts = remote.split(separator: ".").compactMap { Int($0) }
        let localParts = local.split(separator: ".").compactMap { Int($0) }

        for i in 0..<max(remoteParts.count, localParts.count) {
            let r = i < remoteParts.count ? remoteParts[i] : 0
            let l = i < localParts.count ? localParts[i] : 0
            if r > l { return true }
            if r < l { return false }
        }
        return false
    }
}
