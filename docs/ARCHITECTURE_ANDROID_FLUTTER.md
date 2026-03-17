# ChiTV Android (Flutter) 架构设计

## 1. 目标与参考
- 参考一: LibreTV (`LibreSpark/LibreTV`) 的能力侧重
  - 聚合搜索
  - 多源管理/自定义源
  - 视频详情与分集解析
  - 换源与播放链路
  - 播放历史与搜索历史
  - 基础内容过滤
- 参考二: `chitv-app-tvos` iOS/tvOS 的能力侧重
  - 分层服务化 (`NetworkService`, `VODSourceManager`, `FavoritesService`, `PlaybackHistoryService`)
  - 配置持久化与用户偏好
  - 内容过滤/广告过滤
  - 分集/分页与详情加载

## 2. Android Flutter 目标能力 (Phase 1)
- 搜索: 支持关键词在启用数据源上聚合搜索
- 数据源: 默认源 + 自定义源增删改开关 + 持久化
- 详情: 拉取视频详情并解析 `vod_play_url` 生成分集
- 播放: 使用 Android 原生底层播放器能力（`better_native_video_player`）播放 m3u8/mp4
- 历史/收藏:
  - 播放历史（含最近观看时间）
  - 收藏列表
- 设置:
  - 成人内容过滤开关
  - 自动播放下一集开关（预留）

## 3. 分层架构

### 3.1 Presentation
- `features/home`: 搜索页、搜索结果、历史/收藏入口
- `features/detail`: 视频详情与分集列表
- `features/player`: 播放器页
- `features/settings`: 源管理与应用偏好
- 状态管理: `ChangeNotifier`（可在 Phase 2 升级为 Riverpod/Bloc）

### 3.2 Domain (轻量)
- `VideoRepository` 接口（当前在 data 层合并实现）
- 领域实体
  - `VideoItem`
  - `EpisodeItem`
  - `VodSource`
  - `AppSettings`

### 3.3 Data
- `VodApiClient`
  - 请求 `ac=videolist`
  - 请求 `ac=detail`
  - 兼容 `page/pagecount/limit/total` 的 int/string 混合类型
- `LocalStore`
  - 统一持久化（`shared_preferences`）
  - 保存 sources / favorites / history / settings
- `VideoRepository`
  - 聚合多源搜索
  - 详情与分集解析
  - 过滤规则应用

### 3.4 Core
- `ApiResponseParser`: 解码兜底逻辑
- `EpisodeParser`: 解析 `vod_play_url` (`name$url#name$url`)
- `ContentFilter`: 关键词过滤（成人内容）

## 4. 关键数据流
1. 用户输入关键词 -> `HomeController.search()`
2. `VideoRepository.searchAcrossSources()` 并发请求启用源
3. 汇总 + 去重 + 内容过滤 -> UI
4. 用户进入详情 -> `fetchDetail()` -> 解析分集
5. 用户播放 -> `PlayerScreen` + 写入历史

## 5. 与 iOS/tvOS 功能映射
- `VODSourceManager.swift` -> `SourceStore` + `SettingsScreen`
- `NetworkService.swift` -> `VodApiClient`
- `PlaybackHistoryService.swift` -> `HistoryStore`
- `FavoritesService.swift` -> `FavoriteStore`
- `ContentFilterService.swift` -> `ContentFilter`

## 6. 迭代计划
- Phase 1: 主流程可用版本
- Phase 2 (已完成当前轮):
  - 视频源测速（设置页）
  - 字幕 URL 管理（启用开关 + 默认 URL + 最近 URL）
  - 播放器增强（失败自动重试 + 手动重试）
  - 自动下一集（依赖分集上下文）
- Phase 3 (已完成当前轮):
  - 剧集详情页换源弹窗（同名结果聚合后一键切换）
  - 按源测速结果排序候选源
  - 源切换后实时刷新详情与分集
- Phase 4 (已完成当前轮):
  - 账号前的本地配置导入/导出（JSON）
  - 播放 QoS 监控面板 + 设置页汇总重置
- Phase 5:
  - 账号同步（跨设备）
  - 更细粒度播放 QoS 监控（按源/按剧集维度）
