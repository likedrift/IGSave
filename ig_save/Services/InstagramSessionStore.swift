//
//  InstagramSessionStore.swift
//  ig_save
//

import Foundation
import WebKit

enum InstagramSessionStore {
    static let loginURL = URL(string: "https://www.instagram.com/accounts/login/")!

    @MainActor
    static func hasActiveSession() async -> Bool {
        let cookies = await instagramCookies()

        return cookies.contains { cookie in
            cookie.name == "sessionid" && !cookie.value.isEmpty
        }
    }

    @MainActor
    static func cookieHeader(for url: URL) async -> String? {
        guard let host = url.host(percentEncoded: false)?.lowercased() else {
            return nil
        }

        let matchingCookies = await allCookies().filter { cookie in
            cookieMatches(cookie, host: host)
        }

        guard !matchingCookies.isEmpty else {
            return nil
        }

        return HTTPCookie.requestHeaderFields(with: matchingCookies)["Cookie"]
    }

    @MainActor
    private static func instagramCookies() async -> [HTTPCookie] {
        await allCookies().filter { cookie in
            cookieMatches(cookie, host: "www.instagram.com")
        }
    }

    @MainActor
    private static func allCookies() async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }

    private static func cookieMatches(_ cookie: HTTPCookie, host: String) -> Bool {
        let domain = cookie.domain
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()

        return host == domain || host.hasSuffix(".\(domain)")
    }
}
