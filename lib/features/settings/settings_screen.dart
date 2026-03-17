import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_scope.dart';
import '../../core/models/vod_source.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _subtitleController;

  @override
  void initState() {
    super.initState();
    _subtitleController = TextEditingController();
  }

  @override
  void dispose() {
    _subtitleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);

    if (_subtitleController.text != app.settings.defaultSubtitleUrl) {
      _subtitleController.text = app.settings.defaultSubtitleUrl;
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        SwitchListTile(
          value: app.settings.adultFilterEnabled,
          onChanged: app.setAdultFilter,
          title: const Text('成人内容过滤'),
        ),
        SwitchListTile(
          value: app.settings.autoPlayNext,
          onChanged: app.setAutoPlayNext,
          title: const Text('自动播放下一集'),
        ),
        SwitchListTile(
          value: app.settings.subtitleEnabled,
          onChanged: app.setSubtitleEnabled,
          title: const Text('启用字幕（URL）'),
        ),
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
        if (app.settings.recentSubtitleUrls.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
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
          ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Text('配置管理', style: TextStyle(fontWeight: FontWeight.w700)),
            const Spacer(),
            FilledButton.tonal(
              onPressed: () => _showExportDialog(context),
              child: const Text('导出'),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: () => _showImportDialog(context),
              child: const Text('导入'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            title: const Text('QoS 诊断汇总'),
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
        Row(
          children: [
            const Text('视频源管理', style: TextStyle(fontWeight: FontWeight.w700)),
            const Spacer(),
            FilledButton.tonal(
              onPressed: app.probingSources ? null : () => app.refreshSourceSpeeds(),
              child: Text(app.probingSources ? '测速中' : '测速'),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: () => _showSourceEditor(context),
              child: const Text('添加'),
            ),
          ],
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
      ],
    );
  }

  String _formatLatency(int? value) {
    if (value == null) return '不可达';
    return '${value}ms';
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
                if (!ctx.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
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
                  if (!ctx.mounted) return;
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('配置导入成功')),
                  );
                } catch (e) {
                  if (!ctx.mounted) return;
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
        padding: const EdgeInsets.all(12),
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
            Text(
              source.apiUrl,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Text(
              '延迟: $latencyText',
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
                    icon: Icon(source.isDefault ? Icons.lock_outline : Icons.delete_outline, size: 16),
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
