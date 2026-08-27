//
//  MediaAsset.swift
//  ig_save
//

import Foundation

enum MediaKind: String, Codable, Hashable, Sendable {
    case image
    case video
    case unknown

    nonisolated static func infer(from url: URL) -> MediaKind {
        let ext = url.pathExtension.lowercased()

        if ["jpg", "jpeg", "png", "heic", "heif", "webp", "gif"].contains(ext) {
            return .image
        }

        if ["mp4", "mov", "m4v"].contains(ext) {
            return .video
        }

        return .unknown
    }
}

enum InstagramContentKind: String, Codable, Hashable, Sendable {
    case direct
    case post
    case reel
    case story
    case unknown
}

struct MediaResolution: Sendable {
    let assets: [MediaAsset]
    let username: String?
    let contentKind: InstagramContentKind
    let sourceURL: URL
}

struct MediaAsset: Identifiable, Hashable, Sendable {
    let id = UUID()
    let sourceURL: URL
    let kind: MediaKind
    let suggestedFilename: String
}

struct SaveAssetDescriptor: Codable, Equatable, Sendable {
    let sourceURLString: String
    let kind: MediaKind
    let suggestedFilename: String

    init(sourceURLString: String, kind: MediaKind, suggestedFilename: String) {
        self.sourceURLString = sourceURLString
        self.kind = kind
        self.suggestedFilename = suggestedFilename
    }

    init(asset: MediaAsset) {
        sourceURLString = asset.sourceURL.absoluteString
        kind = asset.kind
        suggestedFilename = asset.suggestedFilename
    }

    var asset: MediaAsset? {
        guard let sourceURL = URL(string: sourceURLString) else {
            return nil
        }

        return MediaAsset(
            sourceURL: sourceURL,
            kind: kind,
            suggestedFilename: suggestedFilename
        )
    }
}

struct MediaCandidate: Hashable, Sendable {
    let sourceURL: URL
    let kind: MediaKind
    let priority: Int
}

struct RecentSave: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let username: String
    let savedAt: Date
    let itemCount: Int
    let contentKind: InstagramContentKind
    let sourceURL: String
    let previewFilename: String?

    init(
        id: UUID = UUID(),
        username: String,
        savedAt: Date = Date(),
        itemCount: Int,
        contentKind: InstagramContentKind,
        sourceURL: String,
        previewFilename: String?
    ) {
        self.id = id
        self.username = username
        self.savedAt = savedAt
        self.itemCount = itemCount
        self.contentKind = contentKind
        self.sourceURL = sourceURL
        self.previewFilename = previewFilename
    }
}
