import Foundation
import Testing
@testable import IGSave

struct AppDiagnosticsTests {
    @Test("网络错误会得到稳定代码和恢复建议")
    func classifiesNetworkErrors() {
        let descriptor = AppErrorClassifier.classify(URLError(.timedOut))

        #expect(descriptor.category == .network)
        #expect(descriptor.code == "network.timeout")
        #expect(descriptor.displayMessage.contains("重试"))
    }

    @Test("相册权限错误会提示打开系统权限")
    func classifiesPhotoPermissionErrors() {
        let descriptor = AppErrorClassifier.classify(PhotoLibrarySaverError.permissionDenied)

        #expect(descriptor.category == .photoLibrary)
        #expect(descriptor.code == "photos.permission_denied")
        #expect(descriptor.displayMessage.contains("系统设置"))
    }

    @Test("HTTP 状态会区分限流、权限和失效链接")
    func classifiesHTTPStatusErrors() {
        let rateLimited = AppErrorClassifier.classify(MediaResolverError.httpStatus(429))
        let forbidden = AppErrorClassifier.classify(MediaResolverError.httpStatus(403))
        let expiredMedia = AppErrorClassifier.classify(MediaDownloaderError.httpStatus(404))

        #expect(rateLimited.category == .network)
        #expect(rateLimited.code == "resolver.http_429")
        #expect(forbidden.category == .access)
        #expect(expiredMedia.code == "download.http_404")
        #expect(expiredMedia.displayMessage.contains("重新解析"))
    }

    @Test("诊断文本移除链接账号会话和本机路径")
    func sanitizesPrivateValues() {
        let original = "@likedrift https://instagram.com/p/example sessionid=secret /private/var/mobile/file.mp4"
        let sanitized = DiagnosticSanitizer.sanitize(original)

        #expect(!sanitized.contains("likedrift"))
        #expect(!sanitized.contains("instagram.com"))
        #expect(!sanitized.contains("secret"))
        #expect(!sanitized.contains("/private/var"))
        #expect(sanitized.contains("<链接>"))
        #expect(sanitized.contains("<本机路径>"))
    }
}
