# IGSave Development Progress

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

### 2026-05-04 - Story Avatar Guard

- Diagnosed story links saving the user's avatar because story pages can expose profile/avatar images through Open Graph metadata.
- Added Instagram link target detection:
  - `/p/...`, `/reel/...`, and `/tv/...` use shortcode parsing.
  - `/stories/{username}/{storyID}` uses story ID parsing.
- Disabled Open Graph fallback for story links so avatars are never treated as story media.
- Added story media parsing for:
  - `image_versions2.candidates`
  - `video_versions`
  - `video_url`
- Scoped regex fallback to scripts containing the exact story ID; if real story media is unavailable, the app now fails instead of saving the avatar.

### 2026-05-04 - UI Refresh And Recent Saves

- Recorded story authenticated access as a TODO instead of continuing story work immediately.
- Generated and applied an original 1024px iOS app icon:
  - `AppIcon.png`
  - `AppIcon-Dark.png`
  - `AppIcon-Tinted.png`
- Rebuilt the main screen around an iOS 26 Liquid Glass style:
  - Branded header.
  - Glass input panel.
  - Compact current-task status.
  - Dedicated recent saves area.
- Added persistent recent-save history:
  - Stores the latest 5 successful saves.
  - Tracks username/source, saved time, saved file count, content kind, source URL, and preview thumbnail.
  - Generates local 240px thumbnails from the first saved image, or video frame when needed.

### 2026-05-16 - Instagram Story Support TODO

- Example unsupported story link recorded:
  - `https://www.instagram.com/stories/zutomayo/3897615737682708220?utm_source=ig_story_item_share&igsh=MTZqZTN3cmI1YXVjdg==`
- Current status:
  - Public post/reel links are supported when the page exposes resolvable media metadata.
  - Story links are not reliably supported because real story media usually depends on Instagram login state and authorized requests.
- Observed behavior:
  - Public story HTML may expose only profile/avatar imagery, a shell page, or preview metadata.
  - The app already disables Open Graph fallback for story links so avatars are not saved as story media.
- TODO:
  - Design a compliant story support flow, such as a local WebView login session, Share Extension capture path, or manual media direct-link mode.
  - Do not bypass login, private account restrictions, or other access controls.

### 2026-05-16 - Authenticated Story Prototype

- Added a local Instagram login entry point using an in-app `WKWebView`.
- Story links now require an active Instagram `sessionid` cookie in the app's default WebKit data store.
- When saving `/stories/{username}/{storyID}` links, the app:
  - Loads the story URL in a local `WKWebView` with the user's own Instagram session.
  - Extracts real media candidates from visible `video`/`img` elements and loaded CDN resources.
  - Filters out profile/avatar resources and keeps Open Graph fallback disabled for stories.
- Downloads include Instagram referer and available matching cookies.
- This remains a personal-use authenticated flow; it does not bypass login, private account restrictions, or other access controls.

### 2026-06-22 - iOS 27 Debug DYLIB Fix

- Disabled `ENABLE_DEBUG_DYLIB` (`= NO`) in both Project-level and Target-level Debug build configurations.
- Disabled `ENABLE_PREVIEWS` (`= NO`) in Target Debug (non-functional without debug dylib).
- Disabled `SWIFT_APPROACHABLE_CONCURRENCY` (`= NO`) in Target Debug — suspected dyld crash cause due to Swift 6 runtime mismatch between Xcode 26.4 SDK and iOS 27 beta device.
- Fixes dyld-stage crash (`lsl::MemoryManager::lockGuard()` / refcount decrement) on iOS 27 real devices.
- Side effect: SwiftUI Preview is no longer available in this Debug configuration (accepted tradeoff for reliable device debugging).
- The Release configuration is unchanged.

## Current Status

- Implemented MVP app flow:
  - Paste or type a link.
  - Resolve direct media URLs or public Instagram Open Graph media.
  - Download resolved assets to app cache.
  - Save images/videos into Photos with add-only permission.
  - Show per-link history and failure messages.
- Instagram Story links require an in-app Instagram login session and are saved only when real story media is visible in that session.
- Added Photos add-only usage description to generated Info.plist settings.
- Verified:
  - `ig_save.xcodeproj/project.pbxproj` passes `plutil -lint`.
  - Swift files pass `xcrun swiftc -parse`.
  - Models and services pass `xcrun swiftc -typecheck`.
- Pending verification:
  - Full Xcode/iOS SDK build. Current terminal environment has Command Line Tools only and cannot locate `iphoneos` or `iphonesimulator` SDKs.

### 2026-08-25 - Phase 1: Reliable Save Workflow

- Added a system Share Extension that accepts shared URLs/text and hands the link to IG Save.
- Added an `igsave://import` deep-link entry point for shared content.
- Replaced the single transient save operation with a persistent FIFO task queue.
- Added per-task queued/running/saved/failed/cancelled state, retry, cancellation, removal, and completed-task cleanup.
- Added duplicate-source detection with an explicit “save anyway” recovery path.
- Restores interrupted work as queued tasks on the next app launch.
- Added age/size-based cleanup for downloaded media cache files.
- Verified the app and embedded Share Extension with Xcode 26.6 against the iOS 26.5 device SDK.

### 2026-08-25 - Phase 2: Preview, History, And Recovery

- Manual links now resolve into a media preview before saving.
- Added per-item selection for carousel images and videos before a task enters the queue.
- Expanded recent saves from five entries to a 500-entry file-backed history with automatic migration.
- Added history search, content-type filters, original-link opening, link copying, re-save, delete, and clear-all actions.
- Added an optional dedicated “IG Save” Photos album with the appropriate read/write permission path.
- Added validated Instagram session state, expired-session messaging, explicit logout/cookie cleanup, and a system settings shortcut for permission recovery.
- Unified Debug and Release deployment targets at iOS 26.0.

### 2026-08-25 - Phase 3: Favorites, Shortcuts, And Preferences

- Added persistent favorite profiles with one-tap refresh and per-profile post ID snapshots.
- Refreshing a favorite now reports how many non-story items are new since the previous refresh.
- Added an App Intent and system Shortcuts phrases for sending an Instagram link into the persistent save queue.
- Added pending-import delivery so App Intent requests are consumed while the app is open or on launch.
- Added save-flow preferences for optional preview, duplicate protection, dedicated album organization, and cellular downloads.
- Updated media downloads to honor the cellular-data preference.
- Migrated video thumbnail generation to the current asynchronous AVFoundation APIs.
- Verified App Intents metadata extraction and clean Debug/Release device SDK builds.

### 2026-08-26 - Share Reliability And Unified UI Refinement

- Added a shared App Group handoff so Instagram's Share Extension can reliably queue links even when the main app is not already running.
- Redesigned Share Extension feedback with a compact material confirmation card, success/error haptics, and a readable completion state before dismissal.
- Standardized the product and all user-facing references on the `IGSave` name.
- Simplified the home screen and rebuilt active task cards around compact thumbnails, friendly account/content labels, Liquid Glass actions, batch progress, and automatic removal after success.
- Removed raw source URLs from tasks and recent-save cards; recent saves now use date groups, localized single-line times, compact filters, and a dedicated detail sheet.
- Added bilingual-safe Chinese empty states, consistent Reel/Reels naming, meaningful haptic feedback, batch summaries, and optional local completion notifications.
- Verified clean Debug and Release iOS builds and performed simulator visual QA for the save queue and recent-save layouts.

### 2026-08-30 - Phase 9: First-Run Guidance And Interaction Preferences

- Added a concise first-run guide for new installations covering the Instagram share path, persistent task queue, and local media organization.
- Existing users with saved media, tasks, or followed profiles are migrated without an interrupting onboarding sheet.
- Added a permanent IGSave usage guide inside Settings.
- Added an opt-out preference for haptic feedback and applied it across selection, success, and warning interactions.
- Replaced fixed primary-action heights with Dynamic Type-safe minimum sizing.
- Added automated onboarding policy coverage and performed fresh-install simulator visual QA.

## Next Tasks

- Validate full build in Xcode.
- Test with:
  - A direct JPG/PNG URL.
  - A direct MP4/MOV URL.
  - A public Instagram post/reel URL that exposes `og:image` or `og:video`.
- Test the local-only authenticated story access flow on a real iPhone session; do not bypass login/private access controls.
- Decide story strategy:
  - Manual media URL input.
  - Share extension.
  - Optional authenticated local-only cookie/session flow, if acceptable and compliant.
