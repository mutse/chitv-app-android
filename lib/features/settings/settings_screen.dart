import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_controller.dart';
import '../../app/app_scope.dart';
import '../../app/app_theme.dart';
import '../../core/models/ad_filter.dart';
import '../../core/models/app_settings.dart';
import '../../core/models/vod_source.dart';
import '../../core/update/apk_installer.dart';
import '../../core/update/github_release_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const double _bottomNavHeight = 80;
  static const double _bottomNavOuterMargin = 12;
  static const double _bottomContentSpacing = 20;
  static const String _appDescription =
      'ChiTV Android 客户端，基于 Flutter 构建，提供聚合搜索、播放与视频源管理能力。';
  static const String _author = 'mutse';
  static const String _githubUrl = 'https://github.com/mutse/chitv-app-android';

  late final TextEditingController _subtitleController;
  late final TextEditingController _proxyController;
  late final TextEditingController _hlsProxyController;
  late final TextEditingController _doubanEndpointController;
  final GithubReleaseService _releaseService = GithubReleaseService();
  String _appVersion = '读取中...';
  String _currentVersion = '';
  GithubReleaseInfo? _latestRelease;
  String _updateStatus = '点击检查 GitHub Releases 最新版本';
  bool _checkingForUpdate = false;
  bool _downloadingUpdate = false;
  double? _downloadProgress;

  @override
  void initState() {
    super.initState();
    _subtitleController = TextEditingController();
    _proxyController = TextEditingController();
    _hlsProxyController = TextEditingController();
    _doubanEndpointController = TextEditingController();
    _loadPackageInfo();
  }

  @override
  void dispose() {
    _subtitleController.dispose();
    _proxyController.dispose();
    _hlsProxyController.dispose();
    _doubanEndpointController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);

    if (_subtitleController.text != app.settings.defaultSubtitleUrl) {
      _subtitleController.text = app.settings.defaultSubtitleUrl;
    }
    if (_proxyController.text != app.settings.proxyBaseUrl) {
      _proxyController.text = app.settings.proxyBaseUrl;
    }
    if (_hlsProxyController.text != app.settings.hlsProxyBaseUrl) {
      _hlsProxyController.text = app.settings.hlsProxyBaseUrl;
    }
    if (_doubanEndpointController.text != app.settings.doubanHotEndpoint) {
      _doubanEndpointController.text = app.settings.doubanHotEndpoint;
    }

    return ListView(
      padding: EdgeInsets.fromLTRB(
        12,
        8,
        12,
        MediaQuery.of(context).padding.bottom +
            _bottomNavHeight +
            _bottomNavOuterMargin +
            _bottomContentSpacing,
      ),
      children: [
        Card(
          color: Theme.of(
            context,
          ).colorScheme.primaryContainer.withValues(alpha: 0.42),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surface.withValues(alpha: 0.76),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Settings Overview',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '偏好与系统配置',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  '统一管理播放器、推荐、代理、数据和片源设置。',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _SettingsStatPill(
                      icon: Icons.video_settings_outlined,
                      label: '${app.sources.length} 个视频源',
                    ),
                    _SettingsStatPill(
                      icon: Icons.favorite_outline,
                      label: '${app.favorites.length} 个收藏',
                    ),
                    _SettingsStatPill(
                      icon: Icons.query_stats_outlined,
                      label: '${app.qosSessionCount} 次会话',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const _SectionTitle('常用'),
        _SettingsGroupCard(
          children: [
            _SettingsEntryCard(
              icon: Icons.play_circle_outline_rounded,
              title: '播放与外观',
              subtitle: '播放器偏好、主题模式、字幕 URL 与最近字幕记录',
              stat: _playerAppearanceSummary(app),
              onTap: () => _openSectionPage(
                context,
                title: '播放与外观',
                subtitle: '统一管理播放行为、界面主题和字幕设置。',
                children: [
                  _buildPlayerSection(context, app),
                  const SizedBox(height: 12),
                  _buildAppearanceSection(context, app),
                  const SizedBox(height: 12),
                  _buildSubtitleSection(context, app),
                ],
              ),
            ),
            _SettingsEntryCard(
              icon: Icons.filter_alt_outlined,
              title: '推荐与过滤',
              subtitle: '推荐源、广告过滤、成人内容过滤与豆瓣热门入口',
              stat: _recommendFilterSummary(app),
              onTap: () => _openSectionPage(
                context,
                title: '推荐与过滤',
                subtitle: '把内容推荐和过滤规则收在同一层，减少主页长度。',
                children: [
                  _buildAdFilterSection(context, app),
                  const SizedBox(height: 12),
                  _buildAdultFilterSection(context, app),
                  const SizedBox(height: 12),
                  _buildRecommendSection(context, app),
                ],
              ),
            ),
            _SettingsEntryCard(
              icon: Icons.dns_outlined,
              title: '视频源管理',
              subtitle: '管理聚合搜索与播放所使用的视频源、测速与编辑',
              stat:
                  '${app.sources.where((source) => source.enabled).length}/${app.sources.length} 已启用',
              onTap: () => _openSectionPage(
                context,
                title: '视频源管理',
                subtitle: '维护聚合搜索与播放所需的数据源。',
                children: [_buildSourceSection(context, app)],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const _SectionTitle('系统与维护'),
        _SettingsGroupCard(
          children: [
            _SettingsEntryCard(
              icon: Icons.language_rounded,
              title: '网络与代理',
              subtitle: '管理通用代理、HLS 代理与相关网络转发地址',
              stat: _networkSummary(app),
              onTap: () => _openSectionPage(
                context,
                title: '网络与代理',
                subtitle: '用于处理代理转发和 HLS 专用代理配置。',
                children: [_buildNetworkSection(context, app)],
              ),
            ),
            _SettingsEntryCard(
              icon: Icons.storage_rounded,
              title: '数据与配置',
              subtitle: '导入导出配置、清理历史数据以及查看 QoS 诊断',
              stat: _dataSummary(app),
              onTap: () => _openSectionPage(
                context,
                title: '数据与配置',
                subtitle: '这里放置高频维护项和数据管理操作。',
                children: [
                  _buildConfigSection(context, app),
                  const SizedBox(height: 12),
                  _buildDataSection(context, app),
                  const SizedBox(height: 12),
                  _buildQosSection(context, app),
                ],
              ),
            ),
            _SettingsEntryCard(
              icon: Icons.info_outline_rounded,
              title: '关于应用',
              subtitle: '查看版本、作者、仓库链接和当前应用信息',
              stat: _appVersion,
              onTap: () => _openSectionPage(
                context,
                title: '关于 ChiTV',
                subtitle: '版本、作者与仓库信息。',
                children: [_buildAboutSection(context)],
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _openSectionPage(
    BuildContext context, {
    required String title,
    required String subtitle,
    required List<Widget> children,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _SettingsSectionPage(
          title: title,
          subtitle: subtitle,
          children: children,
        ),
      ),
    );
  }

  String _playerAppearanceSummary(AppController app) {
    final items = <String>[
      app.settings.autoPlayNext ? '连播开' : '连播关',
      app.settings.subtitleEnabled ? '字幕开' : '字幕关',
      _themeModeShortLabel(app.settings.appThemeMode),
    ];
    return items.join(' · ');
  }

  String _recommendFilterSummary(AppController app) {
    return '规则 ${app.settings.adFilters.length} · 豆瓣${app.settings.doubanHotEnabled ? '开' : '关'}';
  }

  String _networkSummary(AppController app) {
    final proxy = app.settings.proxyBaseUrl.trim().isEmpty ? '通用未配' : '通用已配';
    final hls = app.settings.hlsProxyBaseUrl.trim().isEmpty
        ? 'HLS 复用'
        : 'HLS 已配';
    return '$proxy · $hls';
  }

  String _dataSummary(AppController app) {
    return '历史 ${app.history.length} · 搜索 ${app.recentSearches.length} · 收藏 ${app.favorites.length}';
  }

  String _themeModeShortLabel(String value) {
    switch (_normalizeThemeMode(value)) {
      case 'light':
        return '浅色';
      case 'dark':
        return '深色';
      case 'system':
        return '跟随系统';
      default:
        return '跟随系统';
    }
  }

  ShapeBorder _dialogShape() {
    return RoundedRectangleBorder(borderRadius: BorderRadius.circular(24));
  }

  Widget _buildPlayerSection(BuildContext context, AppController app) {
    return _SettingsPanel(
      title: '播放器',
      subtitle: '控制连续播放与单集循环行为。',
      child: Column(
        children: [
          SwitchListTile(
            value: app.settings.autoPlayNext,
            onChanged: app.setAutoPlayNext,
            title: const Text('自动播放下一集'),
          ),
          const Divider(height: 1),
          SwitchListTile(
            value: app.settings.loopPlayback,
            onChanged: app.setLoopPlayback,
            title: const Text('单集循环播放'),
          ),
        ],
      ),
    );
  }

  Widget _buildAppearanceSection(BuildContext context, AppController app) {
    final themeMode = _normalizeThemeMode(app.settings.appThemeMode);
    return _SettingsPanel(
      title: '外观',
      subtitle: '调整应用主题模式。',
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('主题模式'),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 'system', label: Text('跟随系统')),
                ButtonSegment(value: 'light', label: Text('浅色')),
                ButtonSegment(value: 'dark', label: Text('深色')),
              ],
              selected: {themeMode},
              onSelectionChanged: (next) {
                if (next.isEmpty) return;
                app.setAppThemeMode(next.first);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubtitleSection(BuildContext context, AppController app) {
    return _SettingsPanel(
      title: '字幕与辅助',
      subtitle: '管理默认字幕地址和最近使用记录。',
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              value: app.settings.subtitleEnabled,
              onChanged: app.setSubtitleEnabled,
              title: const Text('启用字幕（URL）'),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 8),
            _SettingsFormFieldRow(
              title: '默认字幕 URL',
              description: '支持 `.vtt` 和 `.srt`，播放器会优先加载这里保存的地址。',
              controller: _subtitleController,
              hintText: 'https://example.com/subtitles.vtt',
              buttonLabel: '保存',
              onSubmit: () =>
                  app.setDefaultSubtitleUrl(_subtitleController.text),
            ),
            if (app.settings.recentSubtitleUrls.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                '最近使用',
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: app.settings.recentSubtitleUrls.map<Widget>((url) {
                  return ActionChip(
                    label: SizedBox(
                      width: 220,
                      child: Text(url, overflow: TextOverflow.ellipsis),
                    ),
                    onPressed: () => app.setDefaultSubtitleUrl(url),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAdFilterSection(BuildContext context, AppController app) {
    return _SettingsPanel(
      title: '广告过滤',
      subtitle: '过滤 HLS 分片和广告相关链接。',
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              value: app.settings.hlsAdFilterEnabled,
              onChanged: app.setHlsAdFilterEnabled,
              title: const Text('启用广告过滤'),
              subtitle: const Text('会同时过滤 HLS 分片、搜索结果、剧集列表中的广告链接'),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 8),
            _SettingsActionRow(
              icon: Icons.rule_folder_outlined,
              title: '自定义规则',
              description:
                  '当前 ${app.settings.adFilters.length} 条规则，可用于过滤 URL 或关键片段。',
              buttonLabel: '添加规则',
              onPressed: () => _showAddFilterDialog(context),
            ),
            const SizedBox(height: 8),
            if (app.settings.adFilters.isEmpty)
              const _SettingsInfoTile(
                icon: Icons.inbox_outlined,
                title: '暂无自定义规则',
                description: '添加后会在播放链路和搜索结果中按规则过滤广告链接。',
              )
            else
              ...app.settings.adFilters.map<Widget>((filter) {
                return Column(
                  children: [
                    _SettingsToggleActionRow(
                      value: filter.enabled,
                      onChanged: (value) =>
                          app.toggleAdFilter(filter.id, value),
                      title: filter.pattern,
                      description: filter.type.label,
                      buttonIcon: Icons.delete_outline,
                      buttonTooltip: '删除规则',
                      onAction: () => app.removeAdFilter(filter.id),
                    ),
                    if (filter.id != app.settings.adFilters.last.id)
                      const Divider(height: 1, indent: 14),
                  ],
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildAdultFilterSection(BuildContext context, AppController app) {
    return _SettingsPanel(
      title: '内容过滤',
      subtitle: '在首页和搜索结果中过滤敏感关键词内容。',
      child: SwitchListTile(
        value: app.settings.adultFilterEnabled,
        onChanged: app.setAdultFilter,
        title: const Text('成人内容过滤'),
        subtitle: const Text('在首页、搜索结果中过滤敏感关键词内容'),
      ),
    );
  }

  Widget _buildRecommendSection(BuildContext context, AppController app) {
    return _SettingsPanel(
      title: '推荐配置',
      subtitle: '控制豆瓣热门入口及接口地址。',
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              value: app.settings.doubanHotEnabled,
              onChanged: app.setDoubanHotEnabled,
              title: const Text('启用豆瓣热门推荐'),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 8),
            _SettingsFormFieldRow(
              title: '豆瓣接口地址',
              description: '用于首页热门推荐，留空时会回退到默认接口地址。',
              controller: _doubanEndpointController,
              hintText: AppSettings.defaultDoubanHotEndpoint,
              buttonLabel: '保存',
              onSubmit: () =>
                  app.setDoubanHotEndpoint(_doubanEndpointController.text),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNetworkSection(BuildContext context, AppController app) {
    return _SettingsPanel(
      title: '网络与代理',
      subtitle: '设置通用代理和 HLS 专用代理。',
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SettingsFormFieldRow(
              title: '通用代理地址',
              description: '用于 `/proxy` 请求转发，适合常规视频与接口请求。',
              controller: _proxyController,
              hintText: 'http://127.0.0.1:9978',
              buttonLabel: '保存',
              onSubmit: () => app.setProxyBaseUrl(_proxyController.text),
            ),
            const SizedBox(height: 12),
            _SettingsFormFieldRow(
              title: 'HLS 代理地址',
              description: '为空时复用通用代理，适合单独处理 HLS 播放流。',
              controller: _hlsProxyController,
              hintText: 'http://127.0.0.1:9979',
              buttonLabel: '保存',
              onSubmit: () => app.setHlsProxyBaseUrl(_hlsProxyController.text),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfigSection(BuildContext context, AppController app) {
    return _SettingsPanel(
      title: '配置管理',
      subtitle: '导出或导入当前应用配置。',
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _showExportDialog(context),
                icon: const Icon(Icons.ios_share_outlined),
                label: const Text('导出'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: () => _showImportDialog(context),
                icon: const Icon(Icons.download_outlined),
                label: const Text('导入'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDataSection(BuildContext context, AppController app) {
    return _SettingsPanel(
      title: '数据管理',
      subtitle: '清理历史、搜索和收藏数据。',
      child: Column(
        children: [
          _SettingsDangerRow(
            icon: Icons.history_toggle_off_rounded,
            title: '清空观看历史',
            description: '${app.history.length} 条记录',
            actionLabel: '清空',
            onTap: () => _confirmAndRun(
              context,
              title: '清空观看历史',
              message: '此操作不可恢复，是否继续？',
              onConfirm: app.clearWatchHistory,
            ),
          ),
          const Divider(height: 1, indent: 14),
          _SettingsDangerRow(
            icon: Icons.search_off_rounded,
            title: '清空搜索历史',
            description: '${app.recentSearches.length} 条记录',
            actionLabel: '清空',
            onTap: () => _confirmAndRun(
              context,
              title: '清空搜索历史',
              message: '此操作不可恢复，是否继续？',
              onConfirm: app.clearSearchHistory,
            ),
          ),
          const Divider(height: 1, indent: 14),
          _SettingsDangerRow(
            icon: Icons.heart_broken_outlined,
            title: '清空收藏',
            description: '${app.favorites.length} 条记录',
            actionLabel: '清空',
            onTap: () => _confirmAndRun(
              context,
              title: '清空收藏',
              message: '此操作不可恢复，是否继续？',
              onConfirm: app.clearFavorites,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQosSection(BuildContext context, AppController app) {
    return _SettingsPanel(
      title: 'QoS 诊断汇总',
      subtitle: '查看启动、缓冲、重试和错误统计。',
      child: _SettingsActionRow(
        icon: Icons.monitor_heart_outlined,
        title: '播放质量监控',
        description:
            '会话:${app.qosSessionCount}  平均启动:${app.qosAvgStartupMs}ms\n'
            '缓冲:${app.qosBufferEvents}次/${app.qosBufferTotalMs}ms  '
            '重试:${app.qosRetryCount}  错误:${app.qosErrorCount}',
        buttonLabel: '重置',
        onPressed: app.resetQosStats,
      ),
    );
  }

  Widget _buildSourceSection(BuildContext context, AppController app) {
    return Column(
      children: [
        _SettingsPanel(
          title: '视频源管理',
          subtitle: '维护聚合搜索与播放所需的数据源。',
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: app.probingSources
                        ? null
                        : () => app.refreshSourceSpeeds(),
                    icon: const Icon(Icons.speed),
                    label: Text(app.probingSources ? '测速中' : '测速'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () => _showSourceEditor(context),
                    icon: const Icon(Icons.add),
                    label: const Text('添加'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (app.sources.isEmpty)
          _SettingsPanel(
            title: '源列表',
            subtitle: '当前还没有可用视频源。',
            child: const ListTile(
              leading: Icon(Icons.inbox_outlined),
              title: Text('暂无视频源'),
              subtitle: Text('可以先添加一个自定义源，或稍后再来配置。'),
            ),
          )
        else
          _SettingsPanel(
            title: '源列表',
            subtitle: '按启用状态、延迟和地址查看当前视频源。',
            child: Column(
              children: [
                for (var i = 0; i < app.sources.length; i++) ...[
                  _SourceListRow(
                    source: app.sources[i],
                    latencyText: _formatLatency(
                      app.sourceLatencyMs[app.sources[i].id],
                    ),
                    onToggleEnabled: (v) =>
                        app.upsertSource(app.sources[i].copyWith(enabled: v)),
                    onEdit: () =>
                        _showSourceEditor(context, source: app.sources[i]),
                    onDelete: app.sources[i].isDefault
                        ? null
                        : () => app.deleteSource(app.sources[i].id),
                  ),
                  if (i != app.sources.length - 1)
                    const Divider(height: 1, indent: 14),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildAboutSection(BuildContext context) {
    return _SettingsPanel(
      title: '关于 ChiTV',
      subtitle: '版本、作者与仓库信息。',
      child: Column(
        children: [
          _InfoRow(
            icon: Icons.info_outline,
            title: 'App 描述',
            value: _appDescription,
          ),
          const Divider(height: 1),
          _InfoRow(
            icon: Icons.new_releases_outlined,
            title: '版本号',
            value: _appVersion,
          ),
          const Divider(height: 1),
          _InfoRow(icon: Icons.person_outline, title: '作者', value: _author),
          const Divider(height: 1),
          _InfoRow(
            icon: Icons.code_outlined,
            title: 'GitHub 仓库',
            value: _githubUrl,
            trailing: const Icon(Icons.open_in_new),
            onTap: _openGithubRepo,
            onLongPress: () => _copyToClipboard(_githubUrl, '仓库链接已复制'),
          ),
          if (Platform.isAndroid) ...[
            const Divider(height: 1),
            _UpdateActionTile(
              title: '应用更新',
              subtitle: _buildUpdateSubtitle(),
              buttonLabel: _downloadingUpdate
                  ? '下载中'
                  : _checkingForUpdate
                  ? '检查中'
                  : '检查更新',
              onPressed: _checkingForUpdate || _downloadingUpdate
                  ? null
                  : _checkForUpdates,
              progress: _downloadingUpdate ? _downloadProgress : null,
            ),
          ],
        ],
      ),
    );
  }

  String _formatLatency(int? value) {
    if (value == null) return '不可达';
    return '${value}ms';
  }

  String _normalizeThemeMode(String value) {
    if (value == 'light' || value == 'dark' || value == 'system') {
      return value;
    }
    return 'system';
  }

  Future<void> _loadPackageInfo() async {
    final packageInfo = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() {
      _currentVersion = packageInfo.version;
      _appVersion = '${packageInfo.version} (${packageInfo.buildNumber})';
    });
  }

  String _buildUpdateSubtitle() {
    final release = _latestRelease;
    if (_downloadingUpdate) {
      final percent = ((_downloadProgress ?? 0) * 100)
          .clamp(0, 100)
          .toStringAsFixed(0);
      return '正在下载 APK，进度 $percent%';
    }
    if (release == null) return _updateStatus;
    final latestVersion = release.normalizedVersion.isEmpty
        ? release.tagName
        : release.normalizedVersion;
    final comparison = compareSemanticVersion(latestVersion, _currentVersion);
    if (_currentVersion.isEmpty) {
      return '最新版本 $latestVersion，$_updateStatus';
    }
    if (comparison > 0) {
      return '发现新版本 $latestVersion，当前 $_currentVersion';
    }
    return '当前已是最新版本 $_currentVersion';
  }

  Future<void> _checkForUpdates() async {
    setState(() {
      _checkingForUpdate = true;
      _updateStatus = '正在检查更新...';
    });

    try {
      final release = await _releaseService.fetchLatestRelease();
      if (!mounted) return;
      setState(() {
        _latestRelease = release;
        _updateStatus = '已获取最新发布信息';
      });

      final latestVersion = release.normalizedVersion;
      final hasUpdate =
          latestVersion.isNotEmpty &&
          _currentVersion.isNotEmpty &&
          compareSemanticVersion(latestVersion, _currentVersion) > 0;

      if (hasUpdate) {
        await _showUpdateDialog(release);
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('当前已经是最新版本')));
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _updateStatus = '检查更新失败';
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('检查更新失败: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _checkingForUpdate = false;
        });
      }
    }
  }

  Future<void> _showUpdateDialog(GithubReleaseInfo release) async {
    final asset = release.preferredApkAsset;
    final releaseVersion = release.normalizedVersion.isEmpty
        ? release.tagName
        : release.normalizedVersion;
    final notes = release.body.trim().isEmpty
        ? '此版本未提供更新说明。'
        : release.body.trim();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: _dialogShape(),
          title: Text('发现新版本 $releaseVersion'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '当前版本：${_currentVersion.isEmpty ? _appVersion : _currentVersion}',
                  ),
                  const SizedBox(height: 8),
                  Text('安装包：${asset?.name ?? '未找到 APK 资源'}'),
                  const SizedBox(height: 12),
                  Text(
                    notes,
                    style: Theme.of(dialogContext).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('稍后'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                await _openGithubRepo();
              },
              child: const Text('打开仓库'),
            ),
            FilledButton(
              onPressed: asset == null
                  ? null
                  : () async {
                      Navigator.pop(dialogContext);
                      await _downloadAndInstallRelease(release);
                    },
              child: const Text('下载并安装'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _downloadAndInstallRelease(GithubReleaseInfo release) async {
    final asset = release.preferredApkAsset;
    if (asset == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('最新 Release 中未找到 APK 安装包')));
      return;
    }

    setState(() {
      _downloadingUpdate = true;
      _downloadProgress = 0;
      _updateStatus = '开始下载 ${asset.name}';
    });

    try {
      final file = await _releaseService.downloadAsset(
        asset,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() {
            _downloadProgress = progress;
          });
        },
      );

      if (!mounted) return;
      final installResult = await ApkInstaller.installApk(file.path);
      if (!mounted) return;

      switch (installResult) {
        case ApkInstallResult.launched:
          setState(() {
            _updateStatus = '安装器已打开，请按系统提示完成安装';
          });
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('安装器已打开')));
        case ApkInstallResult.permissionRequired:
          setState(() {
            _updateStatus = '需要授予“安装未知应用”权限';
          });
          await _showInstallPermissionDialog();
        case ApkInstallResult.failed:
          throw Exception('系统未能打开安装器');
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _updateStatus = '下载安装失败';
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('下载安装失败: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _downloadingUpdate = false;
          _downloadProgress = null;
        });
      }
    }
  }

  Future<void> _showInstallPermissionDialog() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: _dialogShape(),
          title: const Text('需要安装权限'),
          content: const Text(
            '当前系统尚未允许 ChiTV 安装未知来源应用，请在下一页中为本应用开启安装权限后，再返回重新点击“检查更新”或“下载并安装”。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                await ApkInstaller.openInstallSettings();
              },
              child: const Text('去设置'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openGithubRepo() async {
    final uri = Uri.parse(_githubUrl);
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (opened || !mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('无法打开仓库链接')));
  }

  Future<void> _copyToClipboard(String text, String message) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _confirmAndRun(
    BuildContext pageContext, {
    required String title,
    required String message,
    required Future<void> Function() onConfirm,
  }) async {
    final approved = await showDialog<bool>(
      context: pageContext,
      builder: (ctx) {
        return AlertDialog(
          shape: _dialogShape(),
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('确认'),
            ),
          ],
        );
      },
    );

    if (approved != true) return;
    await onConfirm();
    if (!pageContext.mounted) return;
    ScaffoldMessenger.of(
      pageContext,
    ).showSnackBar(SnackBar(content: Text('$title 已完成')));
  }

  Future<void> _showExportDialog(BuildContext context) async {
    final app = AppScope.read(context);
    final json = app.exportConfigurationJson();

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: _dialogShape(),
          title: const Text('导出配置 JSON'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(child: SelectableText(json)),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: json));
                if (!context.mounted) return;
                ScaffoldMessenger.of(
                  ctx,
                ).showSnackBar(const SnackBar(content: Text('已复制到剪贴板')));
              },
              child: const Text('复制'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showImportDialog(BuildContext context) async {
    final app = AppScope.read(context);
    final controller = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: _dialogShape(),
          title: const Text('导入配置 JSON'),
          content: SizedBox(
            width: 520,
            child: TextField(
              controller: controller,
              maxLines: 14,
              decoration: const InputDecoration(
                hintText: '粘贴导出的 JSON',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  await app.importConfigurationJson(controller.text.trim());
                  if (!ctx.mounted || !context.mounted) return;
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('配置导入成功')));
                } catch (e) {
                  if (!ctx.mounted || !context.mounted) return;
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('导入失败: $e')));
                }
              },
              child: const Text('导入'),
            ),
          ],
        );
      },
    );

    controller.dispose();
  }

  Future<void> _showSourceEditor(
    BuildContext context, {
    VodSource? source,
  }) async {
    final app = AppScope.of(context);
    final nameCtrl = TextEditingController(text: source?.name ?? '');
    final urlCtrl = TextEditingController(text: source?.apiUrl ?? '');

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: _dialogShape(),
          title: Text(source == null ? '新增视频源' : '编辑视频源'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: '名称'),
              ),
              TextField(
                controller: urlCtrl,
                decoration: const InputDecoration(labelText: 'API URL'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final now = DateTime.now().millisecondsSinceEpoch;
                final newSource = VodSource(
                  id: source?.id ?? 'custom_$now',
                  name: nameCtrl.text.trim(),
                  apiUrl: urlCtrl.text.trim(),
                  enabled: source?.enabled ?? true,
                  isDefault: source?.isDefault ?? false,
                );
                app.upsertSource(newSource);
                Navigator.pop(context);
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    );

    nameCtrl.dispose();
    urlCtrl.dispose();
  }

  Future<void> _showAddFilterDialog(BuildContext context) async {
    final app = AppScope.read(context);
    final patternController = TextEditingController();
    var selectedType = AdFilterType.urlPattern;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocalState) {
            return AlertDialog(
              shape: _dialogShape(),
              title: const Text('新增过滤规则'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<AdFilterType>(
                    initialValue: selectedType,
                    decoration: const InputDecoration(
                      labelText: '规则类型',
                      border: OutlineInputBorder(),
                    ),
                    items: AdFilterType.values.map((type) {
                      return DropdownMenuItem(
                        value: type,
                        child: Text(type.label),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setLocalState(() => selectedType = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: patternController,
                    decoration: const InputDecoration(
                      labelText: '匹配内容',
                      hintText: '例如：doubleclick / ad- / promo',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () async {
                    await app.addAdFilter(
                      pattern: patternController.text,
                      type: selectedType,
                    );
                    if (!ctx.mounted) return;
                    Navigator.pop(ctx);
                  },
                  child: const Text('添加'),
                ),
              ],
            );
          },
        );
      },
    );

    patternController.dispose();
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 2, 6, 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _SettingsEntryCard extends StatelessWidget {
  const _SettingsEntryCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.stat,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String stat;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 20, color: scheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Flexible(child: _SettingsValueBadge(text: stat)),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _SettingsGroupCard extends StatelessWidget {
  const _SettingsGroupCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i != children.length - 1)
              const Divider(height: 1, indent: 66, endIndent: 14),
          ],
        ],
      ),
    );
  }
}

class _SettingsValueBadge extends StatelessWidget {
  const _SettingsValueBadge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 132),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: scheme.secondaryContainer.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.right,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: scheme.onSecondaryContainer,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _SettingsSectionPage extends StatelessWidget {
  const _SettingsSectionPage({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: ChiTvNavTitle(title: title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 28),
        children: [
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  scheme.primaryContainer.withValues(alpha: 0.78),
                  scheme.surfaceContainerHighest.withValues(alpha: 0.92),
                ],
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.surface.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Section',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

class _SettingsPanel extends StatelessWidget {
  const _SettingsPanel({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      color: scheme.surface.withValues(alpha: 0.96),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: scheme.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 14),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Container(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.28),
                ),
              ),
              child: Theme(
                data: Theme.of(context).copyWith(
                  listTileTheme: ListTileThemeData(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 2,
                    ),
                    iconColor: scheme.primary,
                    textColor: scheme.onSurface,
                  ),
                  dividerColor: scheme.outlineVariant.withValues(alpha: 0.3),
                  inputDecorationTheme: InputDecorationTheme(
                    filled: true,
                    fillColor: scheme.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(
                        color: scheme.outlineVariant.withValues(alpha: 0.5),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(
                        color: scheme.outlineVariant.withValues(alpha: 0.5),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(
                        color: scheme.primary.withValues(alpha: 0.7),
                        width: 1.4,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                  ),
                  switchTheme: SwitchThemeData(
                    thumbColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) {
                        return scheme.onPrimary;
                      }
                      return scheme.outline;
                    }),
                    trackColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) {
                        return scheme.primary;
                      }
                      return scheme.surfaceContainerHighest;
                    }),
                  ),
                ),
                child: child,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsStatPill extends StatelessWidget {
  const _SettingsStatPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceListRow extends StatelessWidget {
  const _SourceListRow({
    required this.source,
    required this.latencyText,
    required this.onToggleEnabled,
    required this.onEdit,
    this.onDelete,
  });

  final VodSource source;
  final String latencyText;
  final ValueChanged<bool> onToggleEnabled;
  final VoidCallback onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.cloud_outlined,
                  color: scheme.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      source.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      source.apiUrl,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _SettingsValueBadge(text: '延迟 $latencyText'),
                        _SettingsValueBadge(
                          text: source.enabled ? '已启用' : '已停用',
                        ),
                        if (source.isDefault)
                          const _SettingsValueBadge(text: '默认源'),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Switch(value: source.enabled, onChanged: onToggleEnabled),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit, size: 16),
                  label: const Text('编辑'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: onDelete,
                  icon: Icon(
                    source.isDefault
                        ? Icons.lock_outline
                        : Icons.delete_outline,
                    size: 16,
                  ),
                  label: Text(source.isDefault ? '默认源' : '删除'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.title,
    required this.value,
    this.trailing,
    this.onTap,
    this.onLongPress,
  });

  final IconData icon;
  final String title;
  final String value;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: scheme.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, size: 18, color: scheme.primary),
      ),
      title: Text(title),
      subtitle: Text(
        value,
        maxLines: title == 'App 描述' ? 3 : 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: trailing,
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}

class _UpdateActionTile extends StatelessWidget {
  const _UpdateActionTile({
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    required this.onPressed,
    this.progress,
  });

  final String title;
  final String subtitle;
  final String buttonLabel;
  final VoidCallback? onPressed;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.surface.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.system_update_alt_rounded,
                    size: 18,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (progress != null) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(value: progress),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonal(
                onPressed: onPressed,
                style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                child: Text(buttonLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsFormFieldRow extends StatelessWidget {
  const _SettingsFormFieldRow({
    required this.title,
    required this.description,
    required this.controller,
    required this.hintText,
    required this.buttonLabel,
    required this.onSubmit,
  });

  final String title;
  final String description;
  final TextEditingController controller;
  final String hintText;
  final String buttonLabel;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 420;
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.surface.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(description, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 10),
              if (compact) ...[
                TextField(
                  controller: controller,
                  decoration: InputDecoration(hintText: hintText),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonal(
                    onPressed: onSubmit,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 44),
                    ),
                    child: Text(buttonLabel),
                  ),
                ),
              ] else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: controller,
                        decoration: InputDecoration(hintText: hintText),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonal(
                      onPressed: onSubmit,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(72, 52),
                      ),
                      child: Text(buttonLabel),
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

class _SettingsActionRow extends StatelessWidget {
  const _SettingsActionRow({
    required this.icon,
    required this.title,
    required this.description,
    required this.buttonLabel,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String description;
  final String buttonLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 420;
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.surface.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, size: 18, color: scheme.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          description,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: compact ? double.infinity : null,
                child: FilledButton.tonal(
                  onPressed: onPressed,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(88, 44),
                  ),
                  child: Text(buttonLabel),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SettingsToggleActionRow extends StatelessWidget {
  const _SettingsToggleActionRow({
    required this.value,
    required this.onChanged,
    required this.title,
    required this.description,
    required this.buttonIcon,
    required this.buttonTooltip,
    required this.onAction,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final String title;
  final String description;
  final IconData buttonIcon;
  final String buttonTooltip;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(description),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: onAction,
            tooltip: buttonTooltip,
            icon: Icon(buttonIcon),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _SettingsInfoTile extends StatelessWidget {
  const _SettingsInfoTile({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: scheme.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, size: 18, color: scheme.primary),
      ),
      title: Text(title),
      subtitle: Text(description),
    );
  }
}

class _SettingsDangerRow extends StatelessWidget {
  const _SettingsDangerRow({
    required this.icon,
    required this.title,
    required this.description,
    required this.actionLabel,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final String actionLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: scheme.errorContainer.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, size: 18, color: scheme.onErrorContainer),
      ),
      title: Text(title),
      subtitle: Text(description),
      trailing: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(foregroundColor: scheme.error),
        child: Text(actionLabel),
      ),
      onTap: onTap,
    );
  }
}
