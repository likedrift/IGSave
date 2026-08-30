import Testing
@testable import IGSave

struct UserExperienceTests {
    @Test("全新安装会展示当前版本使用引导")
    func presentsOnboardingForNewInstall() {
        #expect(
            AppPreferences.shouldPresentOnboarding(
                storedVersion: 0,
                hasExistingContent: false
            )
        )
    }

    @Test("已有内容的升级用户不会被引导打断")
    func skipsOnboardingForExistingUser() {
        #expect(
            !AppPreferences.shouldPresentOnboarding(
                storedVersion: 0,
                hasExistingContent: true
            )
        )
    }

    @Test("已看过当前引导后不再重复展示")
    func doesNotRepeatCurrentOnboarding() {
        #expect(
            !AppPreferences.shouldPresentOnboarding(
                storedVersion: AppPreferences.currentOnboardingVersion,
                hasExistingContent: false
            )
        )
    }
}
