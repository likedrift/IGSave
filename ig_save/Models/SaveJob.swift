//
//  SaveJob.swift
//  ig_save
//

import Foundation

enum SaveStatus: Equatable, Sendable, Codable {
    case idle
    case queued
    case resolving
    case downloading(current: Int, total: Int)
    case saving(current: Int, total: Int)
    case cancelling
    case saved(count: Int)
    case partiallySaved(saved: Int, failed: Int, message: String)
    case duplicate(previousSavedAt: Date)
    case failed(String)
    case cancelled

    var title: String {
        switch self {
        case .idle:
            "等待"
        case .queued:
            "等待保存"
        case .resolving:
            "解析中"
        case let .downloading(current, total):
            "下载中 \(current)/\(total)"
        case let .saving(current, total):
            "保存中 \(current)/\(total)"
        case .cancelling:
            "正在取消"
        case let .saved(count):
            "已保存 \(count) 个文件"
        case let .partiallySaved(saved, failed, _):
            "已保存 \(saved)，失败 \(failed)"
        case .duplicate:
            "已经保存过"
        case .failed:
            "失败"
        case .cancelled:
            "已取消"
        }
    }

    var isRunning: Bool {
        switch self {
        case .resolving, .downloading, .saving, .cancelling:
            true
        case .idle, .queued, .saved, .partiallySaved, .duplicate, .failed, .cancelled:
            false
        }
    }

    var isTerminal: Bool {
        switch self {
        case .saved, .partiallySaved, .duplicate, .failed, .cancelled:
            true
        case .idle, .queued, .resolving, .downloading, .saving, .cancelling:
            false
        }
    }
}

enum SaveCompletion {
    static func status(saved: Int, failed: Int, message: String) -> SaveStatus {
        if failed == 0, saved > 0 {
            return .saved(count: saved)
        }

        if saved > 0 {
            return .partiallySaved(saved: saved, failed: failed, message: message)
        }

        return .failed(message)
    }
}

struct SaveJob: Identifiable, Equatable, Sendable, Codable {
    let id: UUID
    let input: String
    let createdAt: Date
    var status: SaveStatus
    var allowsDuplicate: Bool
    var username: String?
    var contentKind: InstagramContentKind?
    var itemCount: Int?
    var previewURLString: String?
    var batchID: UUID?
    var attemptID: UUID?
    var pendingAssets: [SaveAssetDescriptor]?
    var failedAssets: [SaveAssetDescriptor]?
    var successfulAssetCount: Int?
    var failedAssetCount: Int?
    var lastErrorMessage: String?
    var recentSaveID: UUID?
    var updatedAt: Date?

    init(
        id: UUID = UUID(),
        input: String,
        createdAt: Date = Date(),
        status: SaveStatus = .queued,
        allowsDuplicate: Bool = false,
        username: String? = nil,
        contentKind: InstagramContentKind? = nil,
        itemCount: Int? = nil,
        previewURLString: String? = nil,
        batchID: UUID? = nil,
        attemptID: UUID? = nil,
        pendingAssets: [SaveAssetDescriptor]? = nil,
        failedAssets: [SaveAssetDescriptor]? = nil,
        successfulAssetCount: Int? = nil,
        failedAssetCount: Int? = nil,
        lastErrorMessage: String? = nil,
        recentSaveID: UUID? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.input = input
        self.createdAt = createdAt
        self.status = status
        self.allowsDuplicate = allowsDuplicate
        self.username = username
        self.contentKind = contentKind
        self.itemCount = itemCount
        self.previewURLString = previewURLString
        self.batchID = batchID
        self.attemptID = attemptID
        self.pendingAssets = pendingAssets
        self.failedAssets = failedAssets
        self.successfulAssetCount = successfulAssetCount
        self.failedAssetCount = failedAssetCount
        self.lastErrorMessage = lastErrorMessage
        self.recentSaveID = recentSaveID
        self.updatedAt = updatedAt
    }

    mutating func prepareForRetry(forceDuplicate: Bool = false, now: Date = Date()) {
        let completedCount = successfulAssetCount ?? 0
        if completedCount > 0 {
            var retryAssets: [SaveAssetDescriptor] = []
            for asset in (failedAssets ?? []) + (pendingAssets ?? []) where !retryAssets.contains(asset) {
                retryAssets.append(asset)
            }
            pendingAssets = retryAssets
            allowsDuplicate = true
        } else {
            pendingAssets = nil
            successfulAssetCount = 0
            recentSaveID = nil
        }

        failedAssets = []
        failedAssetCount = 0
        lastErrorMessage = nil
        attemptID = nil
        status = .queued
        allowsDuplicate = forceDuplicate || allowsDuplicate
        updatedAt = now
    }
}
