# IG Save Development Progress

## Goal

Build a personal-use iOS app that accepts a pasted Instagram link and saves the linked public media to the local Photos library.

## Scope And Guardrails

- Personal/local use only; no App Store distribution target for now.
- Only save media the user can legally access and has permission to keep.
- Do not bypass Instagram login, private account restrictions, DRM, rate limits, or other access controls.
- First implementation supports:
  - Direct image/video file URLs.
  - Public Instagram post/reel pages when the page exposes Open Graph image/video metadata.
- Stories are tracked as a future item because reliable story access usually requires an authenticated session and should be designed carefully.

## Milestones

### 2026-05-04 - Project Bootstrap

- Found an existing SwiftUI Xcode project in this directory.
- Added this development progress document.
- Planned MVP architecture:
  - `ContentView`: link input and download history UI.
  - `DownloadViewModel`: coordinates resolving, downloading, and saving.
  - `InstagramMediaResolver`: extracts media URLs from direct links or public Instagram metadata.
  - `MediaDownloader`: downloads resolved assets into the app cache.
  - `PhotoLibrarySaver`: saves downloaded images/videos into Photos with add-only permission.

### 2026-05-04 - Build Error Fixes

- Fixed `PhotoLibrarySaver` continuation inference by making the continuation type `CheckedContinuation<Void, Error>`.
- Removed mutable state captured by the Photos `performChanges` closure.
- Marked cross-concurrency model and service types as `Sendable`.
- Rewrote tuple mapping in the HTML metadata parser to avoid Swift closure argument inference issues.
- Made UIKit clipboard access conditional so non-iOS command-line checks can still cover more files.
- Added explicit `Combine` import for `DownloadViewModel` so `ObservableObject` and `@Published` resolve correctly in Xcode.

### 2026-05-04 - Duplicate Media Fix

- Diagnosed duplicate saves from overly broad embedded JSON scraping.
- Removed generic `"url": "*.jpg/mp4"` extraction because it catches repeated page assets, thumbnails, and duplicate CDN variants.
- Kept focused extraction for `display_url` and `video_url`.
- Added media fingerprint de-duplication:
  - Normalize Instagram CDN URLs by media kind, host, and path without volatile query parameters.
  - Keep one best candidate per logical media item.

### 2026-05-04 - Carousel Image Recovery

- Fixed an over-correction where carousel posts could collapse to only a video.
- Added shortcode-aware structured JSON parsing:
  - Extract the shortcode from `/p/...`, `/reel/...`, or `/tv/...` links.
  - Parse Instagram `<script type="application/json">` payloads.
  - Find the media node matching the pasted shortcode.
  - Walk only that media subtree for carousel children.
- Added `image_versions2.candidates` support and choose the highest resolution image candidate for each image item.
- Skip image thumbnails on video nodes so video covers are not saved as extra images.
- Added shortcode-scoped regex fallback:
  - Only search script bodies that contain the pasted shortcode.
  - Use fallback images only when structured parsing found no images.
  - Use fallback videos only when structured parsing found no videos.

## Current Status

- Implemented MVP app flow:
  - Paste or type a link.
  - Resolve direct media URLs or public Instagram Open Graph media.
  - Download resolved assets to app cache.
  - Save images/videos into Photos with add-only permission.
  - Show per-link history and failure messages.
- Added Photos add-only usage description to generated Info.plist settings.
- Verified:
  - `ig_save.xcodeproj/project.pbxproj` passes `plutil -lint`.
  - Swift files pass `xcrun swiftc -parse`.
  - Models and services pass `xcrun swiftc -typecheck`.
- Pending verification:
  - Full Xcode/iOS SDK build. Current terminal environment has Command Line Tools only and cannot locate `iphoneos` or `iphonesimulator` SDKs.

## Next Tasks

- Validate full build in Xcode.
- Test with:
  - A direct JPG/PNG URL.
  - A direct MP4/MOV URL.
  - A public Instagram post/reel URL that exposes `og:image` or `og:video`.
- Decide story strategy:
  - Manual media URL input.
  - Share extension.
  - Optional authenticated local-only cookie/session flow, if acceptable and compliant.
