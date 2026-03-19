import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_scope.dart';
import '../../core/models/ad_filter.dart';
import '../../core/models/app_settings.dart';
import '../../core/models/vod_source.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const String _appDescription = 'ChiTV Android 客户端，基于 Flutter 构建，提供聚合搜索、播放与视频源管理能力。';
  static const String _author = 'mutse';
  static const String _githubUrl = 'https://github.com/mutse/chitv-app-android';

  late final TextEditingController _subtitleController;
  late final TextEditingController _proxyController;
  late final TextEditingController _hlsProxyController;
  late final TextEditingController _doubanEndpointController;
  String _appVersion = '读取中...';

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
    final themeMode = _normalizeThemeMode(app.settings.appThemeMode);

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
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '偏好与系统配置',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
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
        const _SectionTitle('播放器'),
        Card(
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
        ),
        const SizedBox(height: 12),
        const _SectionTitle('外观'),
        Card(
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
        ),
        const SizedBox(height: 12),
        const _SectionTitle('字幕'),
        _SettingsPanel(
          title: '字幕与辅助',
          subtitle: '管理默认字幕地址和最近使用记录。',
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                SwitchListTile(
                  value: app.settings.subtitleEnabled,
                  onChanged: app.setSubtitleEnabled,
                  title: const Text('启用字幕（URL）'),
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _subtitleController,
                        decoration: const InputDecoration(
                          labelText: '默认字幕 URL (.vtt/.srt)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonal(
                      onPressed: () => app.setDefaultSubtitleUrl(_subtitleController.text),
                      child: const Text('保存'),
                    ),
                  ],
                ),
                if (app.settings.recentSubtitleUrls.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: app.settings.recentSubtitleUrls.map((url) {
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
        ),
        const SizedBox(height: 12),
        const _SectionTitle('广告过滤'),
        _SettingsPanel(
          title: '广告过滤',
          subtitle: '过滤 HLS 分片和广告相关链接。',
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                SwitchListTile(
                  value: app.settings.hlsAdFilterEnabled,
                  onChanged: app.setHlsAdFilterEnabled,
                  title: const Text('启用广告过滤'),
                  subtitle: const Text('会同时过滤 HLS 分片、搜索结果、剧集列表中的广告链接'),
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      '自定义规则 ${app.settings.adFilters.length} 条',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const Spacer(),
                    FilledButton.tonalIcon(
                      onPressed: () => _showAddFilterDialog(context),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('添加规则'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (app.settings.adFilters.isEmpty)
                  const ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('暂无自定义规则'),
                  )
                else
                  ...app.settings.adFilters.map((filter) {
                    return Column(
                      children: [
                        SwitchListTile(
                          value: filter.enabled,
                          onChanged: (value) => app.toggleAdFilter(filter.id, value),
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            filter.pattern,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(filter.type.label),
                          secondary: IconButton(
                            onPressed: () => app.removeAdFilter(filter.id),
                            icon: const Icon(Icons.delete_outline),
                            tooltip: '删除规则',
                          ),
                        ),
                        if (filter.id != app.settings.adFilters.last.id)
                          const Divider(height: 1),
                      ],
                    );
                  }),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const _SectionTitle('内容过滤'),
        Card(
          child: SwitchListTile(
            value: app.settings.adultFilterEnabled,
            onChanged: app.setAdultFilter,
            title: const Text('成人内容过滤'),
            subtitle: const Text('在首页、搜索结果中过滤敏感关键词内容'),
          ),
        ),
        const SizedBox(height: 12),
        const _SectionTitle('推荐'),
        _SettingsPanel(
          title: '推荐配置',
          subtitle: '控制豆瓣热门入口及接口地址。',
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                SwitchListTile(
                  value: app.settings.doubanHotEnabled,
                  onChanged: app.setDoubanHotEnabled,
                  title: const Text('启用豆瓣热门推荐'),
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _doubanEndpointController,
                        decoration: const InputDecoration(
                          labelText: '豆瓣接口地址',
                          hintText: AppSettings.defaultDoubanHotEndpoint,
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonal(
                      onPressed: () => app.setDoubanHotEndpoint(_doubanEndpointController.text),
                      child: const Text('保存'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const _SectionTitle('网络代理'),
        _SettingsPanel(
          title: '网络与代理',
          subtitle: '设置通用代理和 HLS 专用代理。',
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _proxyController,
                        decoration: const InputDecoration(
                          labelText: '通用代理地址 (用于 /proxy)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonal(
                      onPressed: () => app.setProxyBaseUrl(_proxyController.text),
                      child: const Text('保存'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _hlsProxyController,
                        decoration: const InputDecoration(
                          labelText: 'HLS 代理地址 (为空时复用通用代理)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonal(
                      onPressed: () => app.setHlsProxyBaseUrl(_hlsProxyController.text),
                      child: const Text('保存'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _SettingsPanel(
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
        ),
        const SizedBox(height: 12),
        const _SectionTitle('数据管理'),
        Card(
          child: Column(
            children: [
              ListTile(
                title: const Text('清空观看历史'),
                subtitle: Text('${app.history.length} 条记录'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _confirmAndRun(
                  context,
                  title: '清空观看历史',
                  message: '此操作不可恢复，是否继续？',
                  onConfirm: app.clearWatchHistory,
                ),
              ),
              const Divider(height: 1),
              ListTile(
                title: const Text('清空搜索历史'),
                subtitle: Text('${app.recentSearches.length} 条记录'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _confirmAndRun(
                  context,
                  title: '清空搜索历史',
                  message: '此操作不可恢复，是否继续？',
                  onConfirm: app.clearSearchHistory,
                ),
              ),
              const Divider(height: 1),
              ListTile(
                title: const Text('清空收藏'),
                subtitle: Text('${app.favorites.length} 条记录'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _confirmAndRun(
                  context,
                  title: '清空收藏',
                  message: '此操作不可恢复，是否继续？',
                  onConfirm: app.clearFavorites,
                ),
              ),
            ],
          ),
        ),
        _SettingsPanel(
          title: 'QoS 诊断汇总',
          subtitle: '查看启动、缓冲、重试和错误统计。',
          child: ListTile(
            title: const Text('播放质量监控'),
            subtitle: Text(
              '会话:${app.qosSessionCount}  平均启动:${app.qosAvgStartupMs}ms\n'
              '缓冲:${app.qosBufferEvents}次/${app.qosBufferTotalMs}ms  '
              '重试:${app.qosRetryCount}  错误:${app.qosErrorCount}',
            ),
            trailing: TextButton(
              onPressed: app.resetQosStats,
              child: const Text('重置'),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _SettingsPanel(
          title: '视频源管理',
          subtitle: '维护聚合搜索与播放所需的数据源。',
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed:
                        app.probingSources ? null : () => app.refreshSourceSpeeds(),
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
        const SizedBox(height: 8),
        if (app.sources.isEmpty)
          const Text('暂无视频源')
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: app.sources.length,
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 320,
              mainAxisExtent: 188,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemBuilder: (context, index) {
              final source = app.sources[index];
              return _SourceGridCard(
                source: source,
                latencyText: _formatLatency(app.sourceLatencyMs[source.id]),
                onToggleEnabled: (v) => app.upsertSource(source.copyWith(enabled: v)),
                onEdit: () => _showSourceEditor(context, source: source),
                onDelete: source.isDefault ? null : () => app.deleteSource(source.id),
              );
            },
          ),
        const SizedBox(height: 12),
        const _SectionTitle('关于'),
        _SettingsPanel(
          title: '关于 ChiTV',
          subtitle: '版本、作者与仓库信息。',
          child: Column(
            children: [
              const ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('App 描述'),
                subtitle: Text(_appDescription),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.new_releases_outlined),
                title: const Text('版本号'),
                subtitle: Text(_appVersion),
              ),
              const Divider(height: 1),
              const ListTile(
                leading: Icon(Icons.person_outline),
                title: Text('作者'),
                subtitle: Text(_author),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.code_outlined),
                title: const Text('GitHub 仓库'),
                subtitle: const Text(_githubUrl),
                trailing: const Icon(Icons.open_in_new),
                onTap: _openGithubRepo,
                onLongPress: () => _copyToClipboard(_githubUrl, '仓库链接已复制'),
              ),
            ],
          ),
        ),
      ],
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
      _appVersion = '${packageInfo.version} (${packageInfo.buildNumber})';
    });
  }

  Future<void> _openGithubRepo() async {
    final uri = Uri.parse(_githubUrl);
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (opened || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('无法打开仓库链接')),
    );
  }

  Future<void> _copyToClipboard(String text, String message) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
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
    ScaffoldMessenger.of(pageContext).showSnackBar(
      SnackBar(content: Text('$title 已完成')),
    );
  }

  Future<void> _showExportDialog(BuildContext context) async {
    final app = AppScope.read(context);
    final json = app.exportConfigurationJson();

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('导出配置 JSON'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: SelectableText(json),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: json));
                if (!context.mounted) return;
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('已复制到剪贴板')),
                );
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
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('配置导入成功')),
                  );
                } catch (e) {
                  if (!ctx.mounted || !context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('导入失败: $e')),
                  );
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

  Future<void> _showSourceEditor(BuildContext context, {VodSource? source}) async {
    final app = AppScope.of(context);
    final nameCtrl = TextEditingController(text: source?.name ?? '');
    final urlCtrl = TextEditingController(text: source?.apiUrl ?? '');

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
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
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
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
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 4),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _SettingsStatPill extends StatelessWidget {
  const _SettingsStatPill({
    required this.icon,
    required this.label,
  });

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

class _SourceGridCard extends StatelessWidget {
  const _SourceGridCard({
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    source.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Switch(
                  value: source.enabled,
                  onChanged: onToggleEnabled,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '延迟: $latencyText',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              source.apiUrl,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const Spacer(),
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
                      source.isDefault ? Icons.lock_outline : Icons.delete_outline,
                      size: 16,
                    ),
                    label: Text(source.isDefault ? '默认源' : '删除'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
