import Foundation

enum BrowserLookupDestination: String, CaseIterable, Identifiable {
    case search, define, translate, documentation
    var id: String { rawValue }
    var title: String {
        switch self {
        case .search: return "Search"
        case .define: return "Define"
        case .translate: return "Translate"
        case .documentation: return "MDN Docs"
        }
    }

    func url(for text: String, language: String = Locale.current.language.languageCode?.identifier ?? "en",
             search: (String) -> URL?) -> URL? {
        switch self {
        case .search: return search(text)
        case .define: return search("define " + text)
        case .documentation: return search(text + " site:developer.mozilla.org")
        case .translate:
            var components = URLComponents(string: "https://translate.google.com/")!
            components.queryItems = [URLQueryItem(name: "sl", value: "auto"), URLQueryItem(name: "tl", value: language),
                                     URLQueryItem(name: "text", value: text), URLQueryItem(name: "op", value: "translate")]
            return components.url
        }
    }

    static func validatedText(_ value: String?) throws -> String {
        let text = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { throw BrowserLookupError.emptyClipboard }
        guard text.utf16.count <= 4000 else { throw BrowserLookupError.tooMuchText }
        return text
    }
}

enum BrowserLookupError: LocalizedError {
    case emptyClipboard, tooMuchText, invalidImage, imageTooLarge
    var errorDescription: String? {
        switch self {
        case .emptyClipboard: return "Copy some text or an image first, then use Look Up Clipboard."
        case .tooMuchText: return "Select a shorter passage — up to 4,000 characters."
        case .invalidImage: return "This image couldn’t be opened. Try copying a PNG, JPEG, or screenshot."
        case .imageTooLarge: return "Choose an image smaller than 25 MB."
        }
    }
}
