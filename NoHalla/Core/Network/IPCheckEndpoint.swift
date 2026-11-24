//
//  IPCheckEndpoint.swift
//  NoHalla
//
//  Known HTTPS IP-check endpoints and shared validation for the macOS app.
//  The extension artifacts carry the same list in `src/endpoints.js`; the app
//  has no CORS constraint, so every HTTPS entry is usable here.
//
//  The app queries main endpoints in parallel every check and checks every
//  valid answer against the trusted list (split-tunnel safety). Fallbacks are
//  queried only when no main endpoint answers; a dead endpoint is ignored and
//  a valid answer that is not trusted closes the gate.
//

import Foundation

enum IPCheckEndpoint {
    /// Same HTTPS entries as the browser extension, minus the HTTP-only
    /// `ip-api.com` endpoint (the app never uses plaintext checks).
    static let presets: [String] = [
        "https://ipinfo.io/ip",
        "https://ipv4.icanhazip.com",
        "https://icanhazip.com",
        "https://ifconfig.co/ip",
        "https://ifconfig.io/ip",
        "https://v4.ident.me",
        "https://ident.me",
        "https://ifconfig.ca/ip",
        "https://ip.gs",
        "https://ip.tyk.nu",
        "https://curlmyip.net",
        "https://wgetip.com",
        "https://myip.wtf/text",
        "https://wtfismyip.com/text",
        "https://ipv4.wtfismyip.com/text",
        "https://myexternalip.com/raw",
        "https://ipecho.net/plain",
        "https://www.trackip.net/ip",
        "https://ipv4.nsupdate.info/myip",
        "https://whatismyip.akamai.com"
    ]

    /// Bounds the parallel request fan-out of one verification batch.
    static let maxCount = 8

    /// The factory main endpoint. It is the only endpoint queried while it
    /// answers; the fallbacks below are used only when no main endpoint does.
    static let defaultMain = "https://ipinfo.io/ip"

    /// Four factory fallbacks. They are queried in parallel only after every
    /// main endpoint failed to return a valid IPv4 answer.
    static let defaultFallbacks = [
        "https://ipv4.icanhazip.com",
        "https://v4.ident.me",
        "https://myexternalip.com/raw",
        "https://ipecho.net/plain"
    ]

    /// HTTPS, a hostname, and no embedded credentials.
    static func isValid(_ string: String) -> Bool {
        guard let url = URL(string: string),
              url.scheme?.lowercased() == "https",
              let host = url.host,
              !host.isEmpty,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.user == nil,
              components.password == nil
        else { return false }
        return true
    }
}