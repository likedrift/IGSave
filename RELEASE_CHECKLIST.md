# IGSave 发布检查清单

## 构建与签名

- [ ] 更新 `MARKETING_VERSION` 与 `CURRENT_PROJECT_VERSION`。
- [ ] 主 App、分享扩展和 App Group 使用同一开发团队及有效签名。
- [ ] Release 构建无编译警告，Archive 和 Validate App 成功。
- [ ] 在最低支持系统与当前系统各完成一次真机启动。

## 核心流程

- [ ] 验证帖子、轮播、Reel、当前快拍和媒体直链。
- [ ] 验证 Instagram → 分享 → 更多 → IGSave 的首次与重复使用。
- [ ] 验证 Wi-Fi/蜂窝网络切换、后台传输、强制退出后的任务恢复。
- [ ] 验证相册拒绝、有限权限、空间不足和失效链接的恢复提示。
- [ ] 验证批量任务的取消、部分成功和仅重试失败项。

## 数据与隐私

- [ ] 确认主 App 与分享扩展均包含有效的 `PrivacyInfo.xcprivacy`。
- [ ] 使用 Xcode Organizer 生成隐私报告并核对 Required Reason API。
- [ ] 确认 App Store Connect 隐私问卷与实际行为一致。
- [ ] 导出一份诊断报告，确认不含完整链接、Cookie、用户名和文件路径。
- [ ] 退出 Instagram 后确认本机会话数据被清除。

## 商店资料与合规

- [ ] 准备隐私政策、支持页面、截图、描述、关键词和年龄分级。
- [ ] 在说明中明确内容仅保存到用户设备，且用户应只保存有权访问的内容。
- [ ] 不暗示与 Instagram 或 Meta 存在官方隶属、授权或合作关系。
- [ ] 完成 TestFlight 内测并记录所有阻塞问题的处理结果。
