//
//  PhotoLibrarySaver.swift
//  ig_save
//

import Foundation
import Photos

enum PhotoLibrarySaverError: LocalizedError, Sendable {
    case permissionDenied
    case unsupportedMedia
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            "没有相册写入权限。"
        case .unsupportedMedia:
            "系统相册不支持这个媒体文件。"
        case .saveFailed:
            "保存到相册失败。"
        }
    }
}

struct PhotoLibrarySaver: Sendable {
    func save(fileURL: URL, kind: MediaKind, albumName: String? = nil) async throws -> String {
        try await requestPermission(requiresLibraryAccess: albumName != nil)

        guard let libraryKind = libraryMediaKind(fileURL: fileURL, preferredKind: kind) else {
            throw PhotoLibrarySaverError.unsupportedMedia
        }

        let identifierBox = AssetIdentifierBox()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                switch libraryKind {
                case .image:
                    identifierBox.value = PHAssetChangeRequest
                        .creationRequestForAssetFromImage(atFileURL: fileURL)?
                        .placeholderForCreatedAsset?
                        .localIdentifier
                case .video:
                    identifierBox.value = PHAssetChangeRequest
                        .creationRequestForAssetFromVideo(atFileURL: fileURL)?
                        .placeholderForCreatedAsset?
                        .localIdentifier
                }
            } completionHandler: { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: PhotoLibrarySaverError.saveFailed)
                }
            }
        }

        guard let identifier = identifierBox.value else {
            throw PhotoLibrarySaverError.saveFailed
        }

        if let albumName {
            try? await addAsset(identifier: identifier, toAlbumNamed: albumName)
        }

        return identifier
    }

    private enum LibraryMediaKind: Sendable {
        case image
        case video
    }

    private func libraryMediaKind(fileURL: URL, preferredKind: MediaKind) -> LibraryMediaKind? {
        switch preferredKind {
        case .image:
            .image
        case .video:
            .video
        case .unknown:
            if hasImageExtension(fileURL) {
                .image
            } else if hasVideoExtension(fileURL) {
                .video
            } else {
                nil
            }
        }
    }

    private func hasImageExtension(_ url: URL) -> Bool {
        ["jpg", "jpeg", "png", "heic", "heif", "webp", "gif"].contains(url.pathExtension.lowercased())
    }

    private func hasVideoExtension(_ url: URL) -> Bool {
        ["mp4", "mov", "m4v"].contains(url.pathExtension.lowercased())
    }

    private func requestPermission(requiresLibraryAccess: Bool) async throws {
        let accessLevel: PHAccessLevel = requiresLibraryAccess ? .readWrite : .addOnly
        let status = PHPhotoLibrary.authorizationStatus(for: accessLevel)

        switch status {
        case .authorized, .limited:
            return
        case .notDetermined:
            let newStatus = await PHPhotoLibrary.requestAuthorization(for: accessLevel)

            guard newStatus == .authorized || newStatus == .limited else {
                throw PhotoLibrarySaverError.permissionDenied
            }
        case .denied, .restricted:
            throw PhotoLibrarySaverError.permissionDenied
        @unknown default:
            throw PhotoLibrarySaverError.permissionDenied
        }
    }

    private func addAsset(identifier: String, toAlbumNamed albumName: String) async throws {
        let album: PHAssetCollection
        if let existing = fetchAlbum(named: albumName) {
            album = existing
        } else {
            let albumIdentifier = AssetIdentifierBox()
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                PHPhotoLibrary.shared().performChanges {
                    albumIdentifier.value = PHAssetCollectionChangeRequest
                        .creationRequestForAssetCollection(withTitle: albumName)
                        .placeholderForCreatedAssetCollection
                        .localIdentifier
                } completionHandler: { success, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if success {
                        continuation.resume(returning: ())
                    } else {
                        continuation.resume(throwing: PhotoLibrarySaverError.saveFailed)
                    }
                }
            }

            guard
                let albumID = albumIdentifier.value,
                let createdAlbum = PHAssetCollection.fetchAssetCollections(
                    withLocalIdentifiers: [albumID],
                    options: nil
                ).firstObject
            else {
                throw PhotoLibrarySaverError.saveFailed
            }
            album = createdAlbum
        }

        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject else {
            throw PhotoLibrarySaverError.saveFailed
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                PHAssetCollectionChangeRequest(for: album)?.addAssets([asset] as NSArray)
            } completionHandler: { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: PhotoLibrarySaverError.saveFailed)
                }
            }
        }
    }

    private func fetchAlbum(named albumName: String) -> PHAssetCollection? {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "title = %@", albumName)
        return PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: options).firstObject
    }
}

private final class AssetIdentifierBox: @unchecked Sendable {
    var value: String?
}
