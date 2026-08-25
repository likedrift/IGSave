//
//  InstagramSessionStore.swift
//  ig_save
//

import Foundation
import WebKit

enum InstagramSessionState: Equatable, Sendable {
    case disconnected
    case connected(username: String?)
    case expired

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

enum InstagramSessionStore {
    static let loginURL = URL(string: "https://www.instagram.com/accounts/login/")!

    @MainActor
    static func hasActiveSession() async -> Bool {
        await localSessionState().isConnected
    }

    @MainActor
    static func validatedSessionState() async -> InstagramSessionState {
        let localState = await localSessionState()
        guard localState.isConnected else {
            return localState
        }

        guard let url = URL(string: "https://www.instagram.com/accounts/edit/") else {
            return localState
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        if let cookieHeader = await cookieHeader(for: url) {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }

        guard
            let (data, response) = try? await URLSession.shared.data(for: request),
            let httpResponse = response as? HTTPURLResponse
        else {
            return localState
        }

        let finalPath = httpResponse.url?.path.lowercased() ?? ""
        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 || finalPath.contains("/accounts/login") {
            return .expired
        }

        let body = String(decoding: data, as: UTF8.self)
        if body.contains("accounts/login") && !body.contains("accounts/edit") {
            return .expired
        }

        return .connected(username: extractedUsername(from: body))
    }

    @MainActor
    static func clearInstagramSession() async {
        let store = WKWebsiteDataStore.default().httpCookieStore
        for cookie in await instagramCookies() {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                store.delete(cookie) {
                    continuation.resume()
                }
            }
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
    private static func localSessionState() async -> InstagramSessionState {
        let cookies = await instagramCookies()
        guard let sessionCookie = cookies.first(where: { $0.name == "sessionid" && !$0.value.isEmpty }) else {
            return .disconnected
        }

        if let expiresDate = sessionCookie.expiresDate, expiresDate <= Date() {
            return .expired
        }

        return .connected(username: nil)
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

    private static func extractedUsername(from body: String) -> String? {
        let patterns = [
            #"\"username\"\s*:\s*\"([^\"]+)\""#,
            #"name=\"username\"[^>]*value=\"([^\"]+)\""#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
                continue
            }
            let range = NSRange(body.startIndex..<body.endIndex, in: body)
            guard
                let match = regex.firstMatch(in: body, range: range),
                let valueRange = Range(match.range(at: 1), in: body)
            else {
                continue
            }
            return String(body[valueRange])
        }

        return nil
    }
}
