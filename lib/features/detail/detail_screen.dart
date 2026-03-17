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
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: SizedBox(
                      height: 220,
                      width: double.infinity,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          detail.poster.isEmpty
                              ? Container(
                                  color: Theme.of(context).colorScheme.surfaceContainer,
                                )
                              : Image.network(
                                  detail.poster,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    color: Theme.of(context).colorScheme.surfaceContainer,
                                  ),
                                ),
                          const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Colors.transparent, Colors.black87],
                              ),
                            ),
                          ),
                          Positioned(
                            left: 14,
                            right: 14,
                            bottom: 14,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  detail.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '当前源: ${_sourceName(app, detail.sourceId)}',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  detail.description.isEmpty ? '暂无简介' : detail.description,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: Colors.black,
                                  ),
                                  onPressed: () {
                                    if (_episodes.isEmpty) {
                                      _openPlayer(context, detail, null, -1);
                                      return;
                                    }
                                    final first = _episodes.first;
                                    _openPlayer(context, detail, first, 0);
                                  },
                                  icon: const Icon(Icons.play_arrow, size: 18),
                                  label: const Text('立即播放'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: _episodes.isEmpty
                      ? GridView.builder(
                          padding: const EdgeInsets.all(12),
                          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 280,
                            mainAxisExtent: 142,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                          ),
                          itemCount: 1,
                          itemBuilder: (context, _) {
                            return _EpisodeGridCard(
                              title: '立即播放',
                              subtitle: detail.url,
                              onPlay: () => _openPlayer(context, detail, null, -1),
                            );
                          },
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _episodes.length,
                          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 280,
                            mainAxisExtent: 142,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                          ),
                          itemBuilder: (context, index) {
                            final ep = _episodes[index];
                            return _EpisodeGridCard(
                              title: ep.name,
                              subtitle: ep.url,
                              onPlay: () => _openPlayer(context, detail, ep, index),
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
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '选择要切换的资源源',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '按测速结果排序，优先更快源',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  itemCount: alternatives.length,
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 280,
                    mainAxisExtent: 170,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemBuilder: (context, index) {
                    final entry = alternatives[index];
                    final latency = app.sourceLatencyMs[entry.source.id];
                    return _SourceSwitchCard(
                      sourceName: entry.source.name,
                      title: entry.video.title,
                      latencyText: latency == null ? '不可达' : '${latency}ms',
                      onSelect: () {
                        Navigator.of(ctx).pop();
                        _switchToSource(entry.video);
                      },
                    );
                  },
                ),
              ),
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

class _EpisodeGridCard extends StatelessWidget {
  const _EpisodeGridCard({
    required this.title,
    required this.subtitle,
    required this.onPlay,
  });

  final String title;
  final String subtitle;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onPlay,
                icon: const Icon(Icons.play_arrow, size: 16),
                label: const Text('播放本集'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceSwitchCard extends StatelessWidget {
  const _SourceSwitchCard({
    required this.sourceName,
    required this.title,
    required this.latencyText,
    required this.onSelect,
  });

  final String sourceName;
  final String title;
  final String latencyText;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              sourceName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const SizedBox(height: 6),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 6),
            Text(
              '延迟: $latencyText',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onSelect,
                child: const Text('切换到此源'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
