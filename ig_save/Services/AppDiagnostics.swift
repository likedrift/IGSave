import Foundation

enum AppErrorCategory: String, Codable, Sendable, CaseIterable {
    case invalidInput
    case authentication
    case access
    case network
    case unavailable
    case photoLibrary
    case storage
    case cancelled
    case unknown

    var title: String {
        switch self {
        case .invalidInput: "链接问题"
        case .authentication: "登录状态"
        case .access: "访问受限"
        case .network: "网络问题"
        case .unavailable: "内容不可用"
        case .photoLibrary: "相册权限"
        case .storage: "存储空间"
        case .cancelled: "已取消"
        case .unknown: "未知问题"
        }
    }
}

struct AppErrorDescriptor: Codable, Equatable, Sendable {
    let category: AppErrorCategory
    let code: String
    let message: String
    let recoverySuggestion: String

    var displayMessage: String {
        guard !recoverySuggestion.isEmpty else { return message }
        return "\(message) \(recoverySuggestion)"
    }
}

enum AppErrorClassifier {
    nonisolated static func classify(_ error: Error) -> AppErrorDescriptor {
        if error is CancellationError {
            return descriptor(.cancelled, "task.cancelled", "任务已取消。", "")
        }

        if let urlError = error as? URLError {
            return classify(urlError)
        }

        if let resolverError = error as? MediaResolverError {
            switch resolverError {
            case .noURL:
                return descriptor(.invalidInput, "resolver.no_url", resolverError, "请粘贴完整的 Instagram 链接后重试。")
            case .unsupportedHost:
                return descriptor(.invalidInput, "resolver.unsupported_host", resolverError, "请改用 Instagram 帖子、Reel、快拍或媒体直链。")
            case .invalidResponse:
                return descriptor(.network, "resolver.invalid_response", resolverError, "请稍后重试；持续失败时可重新连接 Instagram。")
            case .noMediaFound:
                return descriptor(.unavailable, "resolver.no_media", resolverError, "请确认内容未删除且当前账号可以查看。")
            case .storyLoginRequired:
                return descriptor(.authentication, "story.login_required", resolverError, "请先在 IGSave 中连接 Instagram。")
            case .storyMediaUnavailable:
                return descriptor(.unavailable, "story.unavailable", resolverError, "请确认快拍仍在有效期内且当前账号可以查看。")
            }
        }

        if let profileError = error as? InstagramProfileFeedError {
            switch profileError {
            case .invalidUsername:
                return descriptor(.invalidInput, "profile.invalid_username", profileError, "请只输入 Instagram 用户名。")
            case .loginRequired:
                return descriptor(.authentication, "profile.login_required", profileError, "请先连接 Instagram。")
            case .invalidResponse:
                return descriptor(.network, "profile.invalid_response", profileError, "请检查网络或稍后重试。")
            case .noPostsFound:
                return descriptor(.access, "profile.no_posts", profileError, "请确认用户名和当前账号的查看权限。")
            }
        }

        if let photoError = error as? PhotoLibrarySaverError {
            switch photoError {
            case .permissionDenied:
                return descriptor(.photoLibrary, "photos.permission_denied", photoError, "请在系统设置中允许 IGSave 添加照片。")
            case .unsupportedMedia:
                return descriptor(.unavailable, "photos.unsupported_media", photoError, "请重试；若持续失败，原内容可能已失效。")
            case .saveFailed:
                return descriptor(.storage, "photos.save_failed", photoError, "请检查设备空间和相册权限后重试。")
            }
        }

        if error is MediaDownloaderError {
            return descriptor(.network, "download.invalid_response", error, "媒体链接可能已过期，请重新解析并重试。")
        }

        let cocoaError = error as NSError
        if cocoaError.domain == NSCocoaErrorDomain,
           cocoaError.code == CocoaError.Code.fileWriteOutOfSpace.rawValue {
            return descriptor(.storage, "storage.no_space", "设备可用空间不足。", "请释放空间后重试。")
        }

        return descriptor(
            .unknown,
            "unknown.\(cocoaError.domain).\(cocoaError.code)",
            localizedMessage(for: error),
            "请重试；若持续出现，可在设置中导出诊断报告。"
        )
    }

    nonisolated private static func classify(_ error: URLError) -> AppErrorDescriptor {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
            descriptor(.network, "network.\(error.code.rawValue)", "当前网络不可用。", "请检查网络连接后重试。")
        case .timedOut:
            descriptor(.network, "network.timeout", "连接超时。", "请切换网络或稍后重试。")
        case .userAuthenticationRequired, .userCancelledAuthentication:
            descriptor(.authentication, "network.authentication", "Instagram 登录状态不可用。", "请重新连接 Instagram 后重试。")
        case .noPermissionsToReadFile:
            descriptor(.access, "network.access_denied", "当前账号无法访问这项内容。", "请确认内容权限后重试。")
        case .cancelled:
            descriptor(.cancelled, "task.cancelled", "任务已取消。", "")
        default:
            descriptor(.network, "network.\(error.code.rawValue)", "网络请求失败。", "请稍后重试。")
        }
    }

    nonisolated private static func descriptor(
        _ category: AppErrorCategory,
        _ code: String,
        _ error: Error,
        _ recoverySuggestion: String
    ) -> AppErrorDescriptor {
        descriptor(category, code, localizedMessage(for: error), recoverySuggestion)
    }

    nonisolated private static func descriptor(
        _ category: AppErrorCategory,
        _ code: String,
        _ message: String,
        _ recoverySuggestion: String
    ) -> AppErrorDescriptor {
        AppErrorDescriptor(
            category: category,
            code: code,
            message: message,
            recoverySuggestion: recoverySuggestion
        )
    }

    nonisolated private static func localizedMessage(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

enum DiagnosticOutcome: String, Codable, Sendable {
    case success
    case partial
    case failure
}

struct DiagnosticEntry: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let timestamp: Date
    let operation: String
    let outcome: DiagnosticOutcome
    let category: AppErrorCategory?
    let code: String?
    let message: String?
    let context: [String: String]
}

@MainActor
enum DiagnosticStore {
    private static let maximumEntryCount = 100

    static func entries() -> [DiagnosticEntry] {
        guard let data = try? Data(contentsOf: storageURL()),
              let entries = try? JSONDecoder().decode([DiagnosticEntry].self, from: data) else {
            return []
        }
        return entries.sorted { $0.timestamp > $1.timestamp }
    }

    static func record(
        operation: String,
        outcome: DiagnosticOutcome,
        error: AppErrorDescriptor? = nil,
        context: [String: String] = [:]
    ) {
        let entry = DiagnosticEntry(
            id: UUID(),
            timestamp: Date(),
            operation: DiagnosticSanitizer.sanitize(operation),
            outcome: outcome,
            category: error?.category,
            code: error?.code,
            message: error.map { DiagnosticSanitizer.sanitize($0.message) },
            context: context.mapValues(DiagnosticSanitizer.sanitize)
        )
        var updatedEntries = entries()
        updatedEntries.insert(entry, at: 0)
        persist(Array(updatedEntries.prefix(maximumEntryCount)))
    }

    static func clear() {
        try? FileManager.default.removeItem(at: storageURL())
    }

    static func report(for entries: [DiagnosticEntry]? = nil) -> String {
        let reportEntries = entries ?? self.entries()
        let formatter = ISO8601DateFormatter()
        var lines = [
            "IGSave 诊断报告",
            "生成时间：\(formatter.string(from: Date()))",
            "应用版本：\(AppRuntimeInfo.versionDescription)",
            "系统版本：\(ProcessInfo.processInfo.operatingSystemVersionString)",
            "隐私说明：报告已移除完整链接、Instagram 用户名、Cookie 和本机文件路径。",
            "记录数量：\(reportEntries.count)",
            ""
        ]

        for entry in reportEntries {
            let category = entry.category?.rawValue ?? "none"
            let code = entry.code ?? "none"
            let context = entry.context
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\(DiagnosticSanitizer.sanitize($0.value))" }
                .joined(separator: ", ")
            lines.append("[\(formatter.string(from: entry.timestamp))] \(DiagnosticSanitizer.sanitize(entry.operation)) | \(entry.outcome.rawValue) | \(category) | \(code)")
            if let message = entry.message, !message.isEmpty {
                lines.append("  信息：\(DiagnosticSanitizer.sanitize(message))")
            }
            if !context.isEmpty {
                lines.append("  上下文：\(context)")
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func persist(_ entries: [DiagnosticEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        let url = storageURL()
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    private static func storageURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Diagnostics", isDirectory: true)
            .appendingPathComponent("diagnostics-v1.json")
    }
}

enum DiagnosticSanitizer {
    nonisolated static func sanitize(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"(?i)https?://[^\s]+"#, with: "<链接>", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)(?:file://)?/(?:private|var|Users)/[^\s]+"#, with: "<本机路径>", options: .regularExpression)
            .replacingOccurrences(of: #"@[A-Za-z0-9._]+"#, with: "@…", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)(cookie|sessionid)\s*[:=]\s*[^\s,;]+"#, with: "$1=<已移除>", options: .regularExpression)
    }
}

enum AppRuntimeInfo {
    static var versionDescription: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(version) (\(build))"
    }
}
