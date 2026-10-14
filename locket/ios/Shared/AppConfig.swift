import Foundation

/// Values injected through Info.plist from build settings in project.yml,
/// so the app and both extensions read the same configuration.
enum AppConfig {
    static let apiBaseURL: URL = {
        let raw = (Bundle.main.object(forInfoDictionaryKey: "APIBaseURL") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(string: raw) ?? URL(string: "http://localhost:3000")!
    }()

    static let appGroupID: String = Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String ?? ""
}

extension Locale {
    static let ru = Locale(identifier: "ru_RU")
}
