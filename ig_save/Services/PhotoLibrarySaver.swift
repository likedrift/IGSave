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
    func save(fileURL: URL, kind: MediaKind) async throws {
        try await requestAddOnlyPermission()

        guard let libraryKind = libraryMediaKind(fileURL: fileURL, preferredKind: kind) else {
            throw PhotoLibrarySaverError.unsupportedMedia
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                switch libraryKind {
                case .image:
                    _ = PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: fileURL)
                case .video:
                    _ = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
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

    private func requestAddOnlyPermission() async throws {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)

        switch status {
        case .authorized, .limited:
            return
        case .notDetermined:
            let newStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)

            guard newStatus == .authorized || newStatus == .limited else {
                throw PhotoLibrarySaverError.permissionDenied
            }
        case .denied, .restricted:
            throw PhotoLibrarySaverError.permissionDenied
        @unknown default:
            throw PhotoLibrarySaverError.permissionDenied
        }
    }
}
