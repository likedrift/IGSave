//
//  MediaAsset.swift
//  ig_save
//

import Foundation

enum MediaKind: String, Hashable, Sendable {
    case image
    case video
    case unknown

    static func infer(from url: URL) -> MediaKind {
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

struct MediaAsset: Identifiable, Hashable, Sendable {
    let id = UUID()
    let sourceURL: URL
    let kind: MediaKind
    let suggestedFilename: String
}

struct MediaCandidate: Hashable, Sendable {
    let sourceURL: URL
    let kind: MediaKind
    let priority: Int
}
