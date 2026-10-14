import Darwin
import Foundation

/// Distinguishes an address from a search without attempting a network lookup.
enum BrowserAddressInput {
    static func webURL(from input: String) -> URL? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if let url = URL(string: text),
           ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
           let host = url.host, !host.isEmpty {
            return url
        }

        guard text.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              var parts = URLComponents(string: "https://" + text),
              parts.user == nil, parts.password == nil,
              let rawHost = parts.host, !rawHost.isEmpty,
              parts.port.map({ (1...65535).contains($0) }) != false
        else { return nil }

        let host = rawHost.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
        var v4 = in_addr()
        var v6 = in6_addr()
        let isIP = inet_pton(AF_INET, host, &v4) == 1 || inet_pton(AF_INET6, host, &v6) == 1
        let isLocalhost = host == "localhost" || host.hasSuffix(".localhost")
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        let isDomain = labels.count > 1 && labels.allSatisfy { label in
            !label.isEmpty && label.first != "-" && label.last != "-"
                && label.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
        } && labels.last?.contains(where: \.isLetter) == true
        guard isIP || isLocalhost || isDomain else { return nil }

        // Local development servers normally do not have a TLS certificate.
        if isLocalhost || host == "::1" || host.hasPrefix("127.") { parts.scheme = "http" }
        return parts.url
    }
}
