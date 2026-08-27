import Foundation
import UserNotifications

enum NotificationService {
    static func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    static func notifySaveCompletion(successCount: Int, partialCount: Int, failureCount: Int) async {
        guard AppPreferences.sendsCompletionNotifications,
              successCount + failureCount > 0 else { return }

        await requestAuthorizationIfNeeded()
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        let content = UNMutableNotificationContent()
        if partialCount > 0 {
            content.title = "部分内容已保存"
            content.body = "已完成 \(successCount) 个任务，其中 \(partialCount) 个可重试失败项。"
        } else if failureCount == 0 {
            content.title = "保存完成"
            content.body = "IGSave 已完成 \(successCount) 个任务。"
        } else {
            content.title = "保存任务已结束"
            content.body = "完成 \(successCount) 个，\(failureCount) 个需要处理。"
        }
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "igsave-save-\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        try? await UNUserNotificationCenter.current().add(request)
    }
}
