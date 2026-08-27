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
    case saved(count: Int)
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
        case let .saved(count):
            "已保存 \(count) 个文件"
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
        case .resolving, .downloading, .saving:
            true
        case .idle, .queued, .saved, .duplicate, .failed, .cancelled:
            false
        }
    }

    var isTerminal: Bool {
        switch self {
        case .saved, .duplicate, .failed, .cancelled:
            true
        case .idle, .queued, .resolving, .downloading, .saving:
            false
        }
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
        batchID: UUID? = nil
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
    }
}
