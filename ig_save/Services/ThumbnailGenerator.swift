//
//  ThumbnailGenerator.swift
//  ig_save
//

import AVFoundation
import Foundation

#if canImport(UIKit)
import UIKit
#endif

struct ThumbnailGenerator: Sendable {
    func makeThumbnail(for fileURL: URL, kind: MediaKind) async -> String? {
        #if canImport(UIKit)
        guard let image = await sourceImage(for: fileURL, kind: kind) else {
            return nil
        }

        let thumbnail = resizedPreview(from: image, maxDimension: 900)
        let filename = "\(UUID().uuidString).jpg"

        guard
            let data = thumbnail.jpegData(compressionQuality: 0.86),
            let directory = try? RecentSaveStore.previewsDirectory()
        else {
            return nil
        }

        do {
            try data.write(
                to: directory.appendingPathComponent(filename),
                options: [.atomic, .completeFileProtection]
            )
            return filename
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }

    #if canImport(UIKit)
    private func sourceImage(for fileURL: URL, kind: MediaKind) async -> UIImage? {
        switch kind {
        case .image:
            UIImage(contentsOfFile: fileURL.path)
        case .video:
            await videoThumbnail(for: fileURL)
        case .unknown:
            if let image = UIImage(contentsOfFile: fileURL.path) {
                image
            } else {
                await videoThumbnail(for: fileURL)
            }
        }
    }

    private func videoThumbnail(for fileURL: URL) async -> UIImage? {
        let asset = AVURLAsset(url: fileURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true

        do {
            let result = try await generator.image(at: CMTime(seconds: 0.2, preferredTimescale: 600))
            return UIImage(cgImage: result.image)
        } catch {
            return nil
        }
    }

    private func resizedPreview(from image: UIImage, maxDimension: CGFloat) -> UIImage {
        let sourceSize = image.size
        let largestSide = max(sourceSize.width, sourceSize.height)
        let scale = min(maxDimension / largestSide, 1)
        let targetSize = CGSize(
            width: max(1, sourceSize.width * scale),
            height: max(1, sourceSize.height * scale)
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)

        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
    #endif
}
