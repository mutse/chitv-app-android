# ChiTV Android (Flutter)

基于 `LibreTV` 与 `chitv-app-tvos` 功能映射实现的 Flutter Android 版本（第一阶段）。

## 已实现（Phase 1）
- 多源聚合搜索（启用源并发）
- 视频详情 + 分集解析（`vod_play_url`）
- Android 播放器页面（`video_player`）
- 播放历史（本地持久化）
- 收藏功能（本地持久化）
- 设置页：成人内容过滤、自动连播开关、视频源管理

## 已实现（Phase 2）
- 视频源测速（延迟 ms 展示）
- 字幕配置管理（启用开关、默认 URL、最近 URL）
- 播放器容错（自动重试 + 手动重试）
- 自动下一集 + 上一集/下一集手动切换

## 已实现（Phase 3）
- 详情页换源弹窗（同名跨源匹配）
- 候选资源按测速结果排序
- 点击候选源后实时切换当前详情与分集

## 已实现（Phase 4）
- 配置导出/导入（JSON）：覆盖设置、视频源、收藏、历史
- 播放 QoS 监控：
  - 播放器实时面板（启动耗时、缓冲次数/时长、重试、错误）
  - 设置页 QoS 汇总与重置

## 架构文档
- `docs/ARCHITECTURE_ANDROID_FLUTTER.md`

## 目录结构
- `lib/core`: 模型、工具、网络、本地存储
- `lib/app`: 应用级控制器与仓储
- `lib/features`: 页面功能模块（home/detail/player/settings）
- `lib/shared`: 通用组件

## 运行
1. 安装 Flutter 3.22+ 与 Dart 3.3+
2. 执行：
   - `flutter pub get`
   - `flutter run -d android`

## 说明
当前环境没有安装 Flutter SDK，本次先手工完成架构与代码落地；安装 SDK 后即可编译调试。

## GitHub CI/CD（Android 包构建）
- 工作流文件：`.github/workflows/android-build.yml`
- 触发方式：
  - push 到 `main` / `master`
  - 向 `main` / `master` 发起 PR
  - 在 GitHub Actions 页面手动触发（`workflow_dispatch`）
- 构建产物：
  - `app-release.apk`
  - `app-release.aab`
- 产物下载：
  - 进入对应 Actions 运行记录
  - 在 `Artifacts` 区域下载 `app-release-apk` 与 `app-release-aab`

说明：当前仓库未包含 `android/` 目录，CI 中已加入自动兜底（`flutter create --platforms=android .`）。
