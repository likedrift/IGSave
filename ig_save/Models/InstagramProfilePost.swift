//
//  InstagramProfilePost.swift
//  ig_save
//

import Foundation

struct InstagramProfilePost: Identifiable, Hashable, Sendable {
    let id: String
    let url: URL
    let thumbnailURL: URL?
    let contentKind: InstagramContentKind
    let directMediaURL: URL?
    let mediaKind: MediaKind?
}
