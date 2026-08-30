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
    let photoLibraryAssetIDs: [String]
    var isFavorite: Bool
    var collectionIDs: [UUID]
    var tags: [String]
    var note: String?
    var metadataUpdatedAt: Date?

    init(
        id: UUID = UUID(),
        username: String,
        savedAt: Date = Date(),
        itemCount: Int,
        contentKind: InstagramContentKind,
        sourceURL: String,
        previewFilename: String?,
        photoLibraryAssetIDs: [String] = [],
        isFavorite: Bool = false,
        collectionIDs: [UUID] = [],
        tags: [String] = [],
        note: String? = nil,
        metadataUpdatedAt: Date? = nil
    ) {
        self.id = id
        self.username = username
        self.savedAt = savedAt
        self.itemCount = itemCount
        self.contentKind = contentKind
        self.sourceURL = sourceURL
        self.previewFilename = previewFilename
        self.photoLibraryAssetIDs = photoLibraryAssetIDs
        self.isFavorite = isFavorite
        self.collectionIDs = collectionIDs
        self.tags = tags
        self.note = note
        self.metadataUpdatedAt = metadataUpdatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case username
        case savedAt
        case itemCount
        case contentKind
        case sourceURL
        case previewFilename
        case photoLibraryAssetIDs
        case isFavorite
        case collectionIDs
        case tags
        case note
        case metadataUpdatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        username = try container.decode(String.self, forKey: .username)
        savedAt = try container.decode(Date.self, forKey: .savedAt)
        itemCount = try container.decode(Int.self, forKey: .itemCount)
        contentKind = try container.decode(InstagramContentKind.self, forKey: .contentKind)
        sourceURL = try container.decode(String.self, forKey: .sourceURL)
        previewFilename = try container.decodeIfPresent(String.self, forKey: .previewFilename)
        photoLibraryAssetIDs = try container.decodeIfPresent([String].self, forKey: .photoLibraryAssetIDs) ?? []
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        collectionIDs = try container.decodeIfPresent([UUID].self, forKey: .collectionIDs) ?? []
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        note = try container.decodeIfPresent(String.self, forKey: .note)
        metadataUpdatedAt = try container.decodeIfPresent(Date.self, forKey: .metadataUpdatedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(username, forKey: .username)
        try container.encode(savedAt, forKey: .savedAt)
        try container.encode(itemCount, forKey: .itemCount)
        try container.encode(contentKind, forKey: .contentKind)
        try container.encode(sourceURL, forKey: .sourceURL)
        try container.encodeIfPresent(previewFilename, forKey: .previewFilename)
        try container.encode(photoLibraryAssetIDs, forKey: .photoLibraryAssetIDs)
        try container.encode(isFavorite, forKey: .isFavorite)
        try container.encode(collectionIDs, forKey: .collectionIDs)
        try container.encode(tags, forKey: .tags)
        try container.encodeIfPresent(note, forKey: .note)
        try container.encodeIfPresent(metadataUpdatedAt, forKey: .metadataUpdatedAt)
    }
}
