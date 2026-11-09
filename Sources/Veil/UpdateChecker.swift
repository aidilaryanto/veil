import AppKit
import Foundation

@MainActor
final class UpdateChecker {
    static let shared = UpdateChecker()
    private var isChecking = false
    private init() {}

    func check(manual: Bool) async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        do {
            let release = try await fetchLatestRelease()
            guard compareVersions(release.tag, current) > 0 else {
                if manual {
                    showAlert(title: "You're up to date.", message: "Veil \(current) is the latest version.", button: "OK")
                }
                return
            }
            showUpdateAlert(latest: release.tag, current: current, url: release.url)
        } catch {
            if manual {
                showAlert(title: "Could not check for updates.", message: error.localizedDescription, button: "OK")
            }
        }
    }

    private func fetchLatestRelease() async throws -> (tag: String, url: URL) {
        let endpoint = URL(string: "https://api.github.com/repos/aidilaryanto/veil/releases/latest")!
        var request = URLRequest(url: endpoint)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Veil", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let release = try JSONDecoder().decode(Release.self, from: data)
        return (release.tag_name, release.html_url)
    }

    private func compareVersions(_ latest: String, _ current: String) -> Int {
        let latestParts = versionParts(latest)
        let currentParts = versionParts(current)
        for index in 0..<max(latestParts.count, currentParts.count) {
            let left = index < latestParts.count ? latestParts[index] : 0
            let right = index < currentParts.count ? currentParts[index] : 0
            if left != right {
                return left < right ? -1 : 1
            }
        }
        return 0
    }

    private func versionParts(_ version: String) -> [Int] {
        let stripped = version.hasPrefix("v") ? String(version.dropFirst()) : version
        return stripped.split(separator: ".").map { Int($0) ?? 0 }
    }

    private func showAlert(title: String, message: String, button: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: button)
        alert.runModal()
    }

    private func showUpdateAlert(latest: String, current: String, url: URL) {
        let alert = NSAlert()
        alert.messageText = "Veil \(latest) is available."
        alert.informativeText = "You are using Veil \(current). Download the latest version from GitHub."
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(url)
        }
    }

    private struct Release: Decodable {
        let tag_name: String
        let html_url: URL
    }
}
