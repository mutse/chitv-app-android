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
  final _episodeSearchController = TextEditingController();
  String _episodeQuery = '';
  bool _episodeAscending = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _episodeSearchController.dispose();
    super.dispose();
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
    final visibleEpisodes = _visibleEpisodes();

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
                if (_episodes.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _episodeSearchController,
                            onChanged: (value) => setState(() => _episodeQuery = value.trim()),
                            decoration: InputDecoration(
                              isDense: true,
                              hintText: '搜索剧集 / 输入集数',
                              prefixIcon: const Icon(Icons.search),
                              border: const OutlineInputBorder(),
                              suffixIcon: _episodeQuery.isEmpty
                                  ? null
                                  : IconButton(
                                      icon: const Icon(Icons.clear),
                                      onPressed: () {
                                        _episodeSearchController.clear();
                                        setState(() => _episodeQuery = '');
                                      },
                                    ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          tooltip: '快速跳转',
                          onPressed: () => _showEpisodeJumpDialog(detail),
                          icon: const Icon(Icons.numbers),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          tooltip: _episodeAscending ? '倒序' : '正序',
                          onPressed: () {
                            setState(() => _episodeAscending = !_episodeAscending);
                          },
                          icon: Icon(
                            _episodeAscending
                                ? Icons.sort_by_alpha
                                : Icons.sort_by_alpha_outlined,
                          ),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: _episodes.isEmpty
                      ? GridView.builder(
                          padding: const EdgeInsets.all(12),
                          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 280,
                            mainAxisExtent: 260,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                          ),
                          itemCount: 1,
                          itemBuilder: (context, _) {
                            return _EpisodeGridCard(
                              title: '立即播放',
                              imageUrl: detail.poster,
                              onPlay: () => _openPlayer(context, detail, null, -1),
                            );
                          },
                        )
                      : visibleEpisodes.isEmpty
                          ? const Center(child: Text('没有匹配的剧集'))
                          : GridView.builder(
                              padding: const EdgeInsets.all(12),
                              itemCount: visibleEpisodes.length,
                              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 280,
                                mainAxisExtent: 260,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                              ),
                              itemBuilder: (context, index) {
                                final entry = visibleEpisodes[index];
                                final ep = entry.episode;
                                return _EpisodeGridCard(
                                  title: ep.name,
                                  imageUrl: detail.poster,
                                  onPlay: () => _openPlayer(
                                    context,
                                    detail,
                                    ep,
                                    entry.originalIndex,
                                  ),
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

  List<_EpisodeEntry> _visibleEpisodes() {
    final entries = <_EpisodeEntry>[
      for (var i = 0; i < _episodes.length; i++)
        _EpisodeEntry(episode: _episodes[i], originalIndex: i),
    ];

    if (_episodeQuery.isEmpty) {
      final sorted = [...entries];
      if (!_episodeAscending) {
        return sorted.reversed.toList();
      }
      return sorted;
    }

    final query = _episodeQuery.toLowerCase();
    final number = int.tryParse(query);
    final filtered = entries.where((entry) {
      if (number != null && entry.originalIndex + 1 == number) return true;
      return entry.episode.name.toLowerCase().contains(query);
    }).toList();

    if (!_episodeAscending) {
      return filtered.reversed.toList();
    }
    return filtered;
  }

  Future<void> _showEpisodeJumpDialog(VideoItem detail) async {
    if (_episodes.isEmpty) return;
    final jumpCtrl = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('快速跳转'),
          content: TextField(
            controller: jumpCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              hintText: '输入 1 ~ ${_episodes.length}',
              border: const OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final target = int.tryParse(jumpCtrl.text.trim());
                Navigator.pop(ctx);
                if (target == null || target < 1 || target > _episodes.length) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('输入的集数无效')),
                  );
                  return;
                }
                final index = target - 1;
                final episode = _episodes[index];
                _openPlayer(context, detail, episode, index);
              },
              child: const Text('跳转播放'),
            ),
          ],
        );
      },
    );

    jumpCtrl.dispose();
  }
}

class _EpisodeEntry {
  const _EpisodeEntry({
    required this.episode,
    required this.originalIndex,
  });

  final EpisodeItem episode;
  final int originalIndex;
}

class _EpisodeGridCard extends StatelessWidget {
  const _EpisodeGridCard({
    required this.title,
    required this.imageUrl,
    required this.onPlay,
  });

  final String title;
  final String imageUrl;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: imageUrl.isEmpty
                    ? Container(
                        color: Theme.of(context).colorScheme.surfaceContainer,
                        alignment: Alignment.center,
                        child: const Icon(Icons.movie_outlined),
                      )
                    : Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: Theme.of(context).colorScheme.surfaceContainer,
                          alignment: Alignment.center,
                          child: const Icon(Icons.broken_image_outlined),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
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
