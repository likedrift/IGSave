//
//  NetworkRetryPolicy.swift
//  IGSave
//

import Foundation

struct NetworkRetryPolicy: Sendable {
    let maximumAttempts: Int
    let baseDelay: TimeInterval
    let maximumDelay: TimeInterval

    nonisolated init(
        maximumAttempts: Int = 3,
        baseDelay: TimeInterval = 0.7,
        maximumDelay: TimeInterval = 5
    ) {
        self.maximumAttempts = max(1, maximumAttempts)
        self.baseDelay = max(0, baseDelay)
        self.maximumDelay = max(0, maximumDelay)
    }

    nonisolated func shouldRetry(statusCode: Int, afterAttempt attempt: Int) -> Bool {
        guard attempt < maximumAttempts else { return false }
        return [408, 425, 429, 500, 502, 503, 504].contains(statusCode)
    }

    nonisolated func shouldRetry(error: Error, afterAttempt attempt: Int) -> Bool {
        guard attempt < maximumAttempts else { return false }
        guard let urlError = error as? URLError else { return false }

        switch urlError.code {
        case .timedOut,
             .cannotFindHost,
             .cannotConnectToHost,
             .networkConnectionLost,
             .dnsLookupFailed,
             .notConnectedToInternet,
             .internationalRoamingOff,
             .callIsActive,
             .dataNotAllowed,
             .resourceUnavailable:
            return true
        case .cancelled,
             .userAuthenticationRequired,
             .userCancelledAuthentication,
             .noPermissionsToReadFile:
            return false
        default:
            return false
        }
    }

    nonisolated func delay(afterAttempt attempt: Int, retryAfter: String? = nil, now: Date = Date()) -> TimeInterval {
        if let retryAfterDelay = retryAfterDelay(from: retryAfter, now: now) {
            return min(retryAfterDelay, maximumDelay)
        }

        let exponent = max(0, attempt - 1)
        return min(baseDelay * pow(2, Double(exponent)), maximumDelay)
    }

    nonisolated func wait(afterAttempt attempt: Int, retryAfter: String? = nil) async throws {
        let seconds = delay(afterAttempt: attempt, retryAfter: retryAfter)
        guard seconds > 0 else {
            try Task.checkCancellation()
            return
        }
        try await Task.sleep(for: .seconds(seconds))
    }

    nonisolated private func retryAfterDelay(from value: String?, now: Date) -> TimeInterval? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }

        if let seconds = TimeInterval(value), seconds >= 0 {
            return seconds
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        guard let date = formatter.date(from: value) else { return nil }
        return max(0, date.timeIntervalSince(now))
    }
}
