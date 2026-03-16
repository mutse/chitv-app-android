import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app/app_scope.dart';
import '../../core/models/episode_item.dart';
import '../../core/models/video_item.dart';
import '../player/player_screen.dart';

class DetailScreen extends StatefulWidget {
  const DetailScreen({super.key, required this.item});

  final VideoItem item;

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  bool _loading = true;
  bool _switchingSource = false;
  VideoItem? _detail;
  List<EpisodeItem> _episodes = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final app = AppScope.read(context);
    final result = await app.loadDetail(widget.item);
    if (!mounted) return;
    setState(() {
      _detail = result.$1;
      _episodes = result.$2;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final detail = _detail ?? widget.item;

    return Scaffold(
      appBar: AppBar(
        title: Text(detail.title),
        actions: [
          IconButton(
            onPressed: (_loading || _switchingSource) ? null : _showSwitchSourceSheet,
            icon: _switchingSource
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.swap_horiz),
            tooltip: '换源',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (detail.poster.isNotEmpty)
                  SizedBox(
                    height: 180,
                    child: Image.network(detail.poster, fit: BoxFit.cover),
                  ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        detail.description.isEmpty ? '暂无简介' : detail.description,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '当前源: ${_sourceName(app, detail.sourceId)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: _episodes.isEmpty
                      ? ListView(
                          children: [
                            ListTile(
                              title: const Text('立即播放'),
                              subtitle: Text(detail.url),
                              onTap: () => _openPlayer(context, detail, null, -1),
                            ),
                          ],
                        )
                      : ListView.builder(
                          itemCount: _episodes.length,
                          itemBuilder: (context, index) {
                            final ep = _episodes[index];
                            return ListTile(
                              title: Text(ep.name),
                              subtitle: Text(ep.url),
                              onTap: () => _openPlayer(context, detail, ep, index),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Future<void> _showSwitchSourceSheet() async {
    final app = AppScope.read(context);
    final current = _detail ?? widget.item;

    setState(() => _switchingSource = true);
    final alternatives = await app.searchAlternativeSources(current);
    if (!mounted) return;
    setState(() => _switchingSource = false);

    if (alternatives.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未找到可切换的同名资源')),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: ListView(
            children: [
              const ListTile(
                title: Text('选择要切换的资源源'),
                subtitle: Text('按测速结果排序，优先更快源'),
              ),
              ...alternatives.map((entry) {
                final latency = app.sourceLatencyMs[entry.source.id];
                return ListTile(
                  title: Text(entry.source.name),
                  subtitle: Text(
                    '${entry.video.title}  ·  延迟: ${latency == null ? '不可达' : '${latency}ms'}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _switchToSource(entry.video);
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }

  Future<void> _switchToSource(VideoItem target) async {
    final app = AppScope.read(context);
    setState(() {
      _loading = true;
      _switchingSource = true;
    });

    final result = await app.loadDetail(target);
    if (!mounted) return;

    setState(() {
      _detail = result.$1;
      _episodes = result.$2;
      _loading = false;
      _switchingSource = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已切换到 ${_sourceName(app, target.sourceId)}')),
    );
  }

  void _openPlayer(
    BuildContext context,
    VideoItem detail,
    EpisodeItem? episode,
    int index,
  ) {
    final playable = VideoItem(
      id: detail.id,
      title: episode == null ? detail.title : '${detail.title} ${episode.name}',
      description: detail.description,
      poster: detail.poster,
      url: episode?.url ?? detail.url,
      sourceId: detail.sourceId,
      vodPlayUrl: detail.vodPlayUrl,
    );

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlayerScreen(
          item: playable,
          episodes: _episodes,
          currentEpisodeIndex: index,
          seriesTitle: detail.title,
        ),
      ),
    );
  }

  String _sourceName(AppController app, String sourceId) {
    for (final s in app.sources) {
      if (s.id == sourceId) return s.name;
    }
    return sourceId;
  }
}
