//
//  SaveJob.swift
//  ig_save
//

import Foundation

enum SaveStatus: Equatable, Sendable {
    case idle
    case resolving
    case downloading(current: Int, total: Int)
    case saving(current: Int, total: Int)
    case saved(count: Int)
    case failed(String)

    var title: String {
        switch self {
        case .idle:
            "等待"
        case .resolving:
            "解析中"
        case let .downloading(current, total):
            "下载中 \(current)/\(total)"
        case let .saving(current, total):
            "保存中 \(current)/\(total)"
        case let .saved(count):
            "已保存 \(count) 个文件"
        case .failed:
            "失败"
        }
    }

    var isRunning: Bool {
        switch self {
        case .resolving, .downloading, .saving:
            true
        case .idle, .saved, .failed:
            false
        }
    }
}

struct SaveJob: Identifiable, Equatable, Sendable {
    let id = UUID()
    let input: String
    let createdAt = Date()
    var status: SaveStatus = .idle
}
