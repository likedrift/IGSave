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
    func makeThumbnail(for fileURL: URL, kind: MediaKind) -> String? {
        #if canImport(UIKit)
        guard let image = sourceImage(for: fileURL, kind: kind) else {
            return nil
        }

        let thumbnail = squareThumbnail(from: image, side: 240)
        let filename = "\(UUID().uuidString).jpg"

        guard
            let data = thumbnail.jpegData(compressionQuality: 0.82),
            let directory = try? RecentSaveStore.previewsDirectory()
        else {
            return nil
        }

        do {
            try data.write(to: directory.appendingPathComponent(filename), options: .atomic)
            return filename
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }

    #if canImport(UIKit)
    private func sourceImage(for fileURL: URL, kind: MediaKind) -> UIImage? {
        switch kind {
        case .image:
            UIImage(contentsOfFile: fileURL.path)
        case .video:
            videoThumbnail(for: fileURL)
        case .unknown:
            UIImage(contentsOfFile: fileURL.path) ?? videoThumbnail(for: fileURL)
        }
    }

    private func videoThumbnail(for fileURL: URL) -> UIImage? {
        let asset = AVAsset(url: fileURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true

        do {
            let cgImage = try generator.copyCGImage(
                at: CMTime(seconds: 0.2, preferredTimescale: 600),
                actualTime: nil
            )

            return UIImage(cgImage: cgImage)
        } catch {
            return nil
        }
    }

    private func squareThumbnail(from image: UIImage, side: CGFloat) -> UIImage {
        let sourceSize = image.size
        let scale = max(side / sourceSize.width, side / sourceSize.height)
        let scaledSize = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        let origin = CGPoint(
            x: (side - scaledSize.width) / 2,
            y: (side - scaledSize.height) / 2
        )
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))

        return renderer.image { _ in
            image.draw(in: CGRect(origin: origin, size: scaledSize))
        }
    }
    #endif
}
