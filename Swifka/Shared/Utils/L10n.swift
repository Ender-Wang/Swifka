import Foundation

@Observable
final class L10n: @unchecked Sendable {
    static let shared = L10n()

    var locale: String {
        didSet {
            if locale != oldValue {
                loadStrings()
                UserDefaults.standard.set(locale, forKey: "app.locale")
            }
        }
    }

    private var strings: [String: String] = [:]

    private init() {
        locale = UserDefaults.standard.string(forKey: "app.locale") ?? "system"
        loadStrings()
    }

    private func loadStrings() {
        let resolvedLocale = resolveLocale()
        let fileName = resolvedLocale

        guard let url = Bundle.main.url(
            forResource: fileName,
            withExtension: "json",
            subdirectory: "Resources/Locales",
        ) else {
            // Fallback: try without subdirectory (flat bundle)
            if let fallbackURL = Bundle.main.url(forResource: fileName, withExtension: "json") {
                loadFromURL(fallbackURL)
            }
            return
        }
        loadFromURL(url)
    }

    private func loadFromURL(_ url: URL) {
        do {
            let data = try Data(contentsOf: url)
            if let dict = try JSONSerialization.jsonObject(with: data) as? [String: String] {
                strings = dict
            }
        } catch {
            print("L10n: Failed to load strings from \(url): \(error)")
        }
    }

    private func resolveLocale() -> String {
        if locale != "system" {
            return locale
        }
        let preferred = Locale.preferredLanguages.first ?? "en"
        if preferred.hasPrefix("zh") {
            return "zh-Hans"
        }
        return "en"
    }

    func t(_ key: String, _ args: String...) -> String {
        var result = strings[key] ?? key
        for (index, arg) in args.enumerated() {
            result = result.replacingOccurrences(of: "{\(index)}", with: arg)
        }
        return result
    }

    subscript(_ key: String) -> String {
        t(key)
    }
}
