import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app/app_scope.dart';
import '../../app/app_theme.dart';
import '../../core/models/episode_item.dart';
import '../../core/models/playback_history_item.dart';
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
  _EpisodeStatusFilter _episodeStatusFilter = _EpisodeStatusFilter.all;
  _EpisodeSortMode _episodeSortMode = _EpisodeSortMode.episodeOrder;

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
    final visibleEpisodes = _visibleEpisodes(app, detail);
    final resumeEntry = app.findHistoryForVideo(detail);
    final resumeTarget = _resolveResumeTarget(resumeEntry);
    final nextUnwatched = _findNextUnwatchedEpisode(app, detail);
    final episodeStats = _episodeSummaryStats(app, detail);
    final overviewBadges = _episodeOverviewBadges(
      resumeEntry: resumeEntry,
      resumeTarget: resumeTarget,
      nextUnwatched: nextUnwatched,
      episodeStats: episodeStats,
    );
    final canResume =
        resumeEntry != null &&
        resumeEntry.lastPositionSeconds > 0 &&
        (_episodes.isEmpty || (resumeTarget?.index ?? -1) >= 0);

    return Scaffold(
      extendBody: true,
      appBar: AppBar(
        title: ChiTvNavTitle(title: detail.title),
        actions: [
          IconButton(
            onPressed: (_loading || _switchingSource)
                ? null
                : _showSwitchSourceSheet,
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
      body: ChiTvBackground(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                      child: Card(
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            SizedBox(
                              height: 260,
                              width: double.infinity,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  detail.poster.isEmpty
                                      ? Container(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.surfaceContainer,
                                        )
                                      : Image.network(
                                          detail.poster,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) =>
                                              Container(
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.surfaceContainer,
                                              ),
                                        ),
                                  DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          Colors.transparent,
                                          context.chitvTheme.overlayPanelHeavy,
                                        ],
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    left: 18,
                                    right: 18,
                                    bottom: 18,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 5,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(
                                              alpha: 0.18,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              999,
                                            ),
                                          ),
                                          child: Text(
                                            _sourceName(app, detail.sourceId),
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        Text(
                                          detail.title,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 24,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          detail.description.isEmpty
                                              ? '暂无简介'
                                              : detail.description,
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 13,
                                          ),
                                        ),
                                        if (overviewBadges.isNotEmpty) ...[
                                          const SizedBox(height: 10),
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 8,
                                            children: overviewBadges.map((
                                              badge,
                                            ) {
                                              return _EpisodeOverviewBadge(
                                                badge: badge,
                                              );
                                            }).toList(),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: FilledButton.icon(
                                      style: FilledButton.styleFrom(
                                        backgroundColor: Colors.white,
                                        foregroundColor: Colors.black,
                                      ),
                                      onPressed: () {
                                        if (canResume) {
                                          _openPlayer(
                                            context,
                                            detail,
                                            resumeTarget?.episode,
                                            resumeTarget?.index ?? -1,
                                          );
                                          return;
                                        }
                                        if (_episodes.isEmpty) {
                                          _openPlayer(
                                            context,
                                            detail,
                                            null,
                                            -1,
                                            resumeFromHistory: false,
                                          );
                                          return;
                                        }
                                        final first = _episodes.first;
                                        _openPlayer(
                                          context,
                                          detail,
                                          first,
                                          0,
                                          resumeFromHistory: false,
                                        );
                                      },
                                      icon: const Icon(
                                        Icons.play_arrow,
                                        size: 18,
                                      ),
                                      label: Text(
                                        canResume
                                            ? _resumeButtonLabel(
                                                resumeEntry,
                                                resumeTarget,
                                              )
                                            : (_episodes.isEmpty
                                                  ? '立即播放'
                                                  : '播放第 1 集'),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: (_loading || _switchingSource)
                                          ? null
                                          : () {
                                              if (canResume) {
                                                if (_episodes.isEmpty) {
                                                  _openPlayer(
                                                    context,
                                                    detail,
                                                    null,
                                                    -1,
                                                    resumeFromHistory: false,
                                                  );
                                                  return;
                                                }
                                                final first = _episodes.first;
                                                _openPlayer(
                                                  context,
                                                  detail,
                                                  first,
                                                  0,
                                                  resumeFromHistory: false,
                                                );
                                                return;
                                              }
                                              _showSwitchSourceSheet();
                                            },
                                      icon: Icon(
                                        canResume
                                            ? Icons.replay_rounded
                                            : Icons.swap_horiz,
                                        size: 18,
                                      ),
                                      label: Text(canResume ? '从头播放' : '切换片源'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (_episodes.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '剧集列表',
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '共 ${_episodes.length} 集，可按名称搜索或按集数快速跳转',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: episodeStats.map((stat) {
                                    return _EpisodeSummaryChip(stat: stat);
                                  }).toList(),
                                ),
                                if (canResume && resumeTarget != null) ...[
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary
                                          .withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.play_circle_outline_rounded,
                                          size: 18,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.primary,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            _resumeSummaryText(
                                              resumeEntry,
                                              resumeTarget,
                                            ),
                                            style: Theme.of(
                                              context,
                                            ).textTheme.bodySmall,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                if (!canResume && nextUnwatched != null) ...[
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .secondaryContainer
                                          .withValues(alpha: 0.5),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.playlist_play_rounded,
                                          size: 18,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.primary,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            '下一未看集：第 ${nextUnwatched.originalIndex + 1} 集 ${nextUnwatched.episode.name}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(
                                              context,
                                            ).textTheme.bodySmall,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        FilledButton.tonal(
                                          onPressed: () => _openPlayer(
                                            context,
                                            detail,
                                            nextUnwatched.episode,
                                            nextUnwatched.originalIndex,
                                            resumeFromHistory: false,
                                          ),
                                          child: const Text('播放'),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: _episodeSearchController,
                                        onChanged: (value) => setState(
                                          () => _episodeQuery = value.trim(),
                                        ),
                                        decoration: InputDecoration(
                                          isDense: true,
                                          hintText: '搜索剧集 / 输入集数',
                                          prefixIcon: const Icon(Icons.search),
                                          suffixIcon: _episodeQuery.isEmpty
                                              ? null
                                              : IconButton(
                                                  icon: const Icon(Icons.clear),
                                                  onPressed: () {
                                                    _episodeSearchController
                                                        .clear();
                                                    setState(
                                                      () => _episodeQuery = '',
                                                    );
                                                  },
                                                ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton.filledTonal(
                                      tooltip: '快速跳转',
                                      onPressed: () =>
                                          _showEpisodeJumpDialog(detail),
                                      icon: const Icon(Icons.numbers),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton.filledTonal(
                                      tooltip:
                                          _episodeSortMode ==
                                              _EpisodeSortMode.episodeOrder
                                          ? '按最近观看排序'
                                          : '按集数排序',
                                      onPressed: () {
                                        setState(() {
                                          _episodeSortMode =
                                              _episodeSortMode ==
                                                  _EpisodeSortMode.episodeOrder
                                              ? _EpisodeSortMode.recentWatched
                                              : _EpisodeSortMode.episodeOrder;
                                        });
                                      },
                                      icon: Icon(
                                        _episodeSortMode ==
                                                _EpisodeSortMode.episodeOrder
                                            ? Icons.schedule_rounded
                                            : Icons
                                                  .format_list_numbered_rounded,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: _EpisodeStatusFilter.values.map((
                                    filter,
                                  ) {
                                    return ChoiceChip(
                                      label: Text(filter.label),
                                      selected: _episodeStatusFilter == filter,
                                      onSelected: (_) {
                                        setState(
                                          () => _episodeStatusFilter = filter,
                                        );
                                      },
                                    );
                                  }).toList(),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (_episodes.isEmpty)
                    SliverPadding(
                      padding: const EdgeInsets.all(12),
                      sliver: SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 280,
                              mainAxisExtent: 260,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                            ),
                        delegate: SliverChildBuilderDelegate((context, _) {
                          return _EpisodeGridCard(
                            title: '立即播放',
                            imageUrl: detail.poster,
                            subtitle: '当前资源暂未提供分集信息',
                            statusText: canResume
                                ? _resumeSummaryText(resumeEntry, resumeTarget)
                                : '当前资源暂未提供分集信息',
                            markers: const [],
                            actionLabel: canResume ? '继续播放' : '立即播放',
                            onPlay: () =>
                                _openPlayer(context, detail, null, -1),
                            highlight: canResume,
                          );
                        }, childCount: 1),
                      ),
                    )
                  else if (visibleEpisodes.isEmpty)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(child: Text('没有匹配的剧集')),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                      sliver: SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 280,
                              mainAxisExtent: 260,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                            ),
                        delegate: SliverChildBuilderDelegate((context, index) {
                          final entry = visibleEpisodes[index];
                          final ep = entry.episode;
                          return _EpisodeGridCard(
                            title: ep.name,
                            imageUrl: detail.poster,
                            subtitle: '第 ${entry.originalIndex + 1} 集',
                            statusText: _episodeStatusText(entry.history),
                            markers: _episodeMarkers(
                              entry,
                              resumeTarget: resumeTarget,
                              nextUnwatched: nextUnwatched,
                            ),
                            progressValue: _episodeProgressValue(entry.history),
                            actionLabel: _episodeActionLabel(
                              entry,
                              resumeTarget: resumeTarget,
                              nextUnwatched: nextUnwatched,
                            ),
                            highlight:
                                canResume &&
                                resumeTarget?.index == entry.originalIndex,
                            onPlay: () => _openPlayer(
                              context,
                              detail,
                              ep,
                              entry.originalIndex,
                            ),
                          );
                        }, childCount: visibleEpisodes.length),
                      ),
                    ),
                ],
              ),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('未找到可切换的同名资源')));
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
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text('按测速结果排序，优先更快源', style: TextStyle(fontSize: 12)),
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
    int index, {
    bool resumeFromHistory = true,
  }) {
    final app = AppScope.read(context);
    final playable = VideoItem(
      id: detail.id,
      title: episode == null ? detail.title : '${detail.title} ${episode.name}',
      description: detail.description,
      poster: detail.poster,
      url: episode?.url ?? detail.url,
      sourceId: detail.sourceId,
      vodPlayUrl: detail.vodPlayUrl,
    );
    final resumeEntry = resumeFromHistory
        ? app.findHistoryForVideo(playable)
        : null;

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlayerScreen(
          item: playable,
          episodes: _episodes,
          currentEpisodeIndex: index,
          seriesTitle: detail.title,
          initialPositionSeconds: resumeEntry?.lastPositionSeconds ?? 0,
        ),
      ),
    );
  }

  _ResumeTarget? _resolveResumeTarget(PlaybackHistoryItem? entry) {
    if (entry == null) return null;
    if (_episodes.isEmpty) {
      return const _ResumeTarget(episode: null, index: -1);
    }

    final index = _episodes.indexWhere(
      (episode) => episode.url == entry.video.url,
    );
    if (index >= 0) {
      return _ResumeTarget(episode: _episodes[index], index: index);
    }

    return const _ResumeTarget(episode: null, index: -1);
  }

  String _resumeButtonLabel(PlaybackHistoryItem entry, _ResumeTarget? target) {
    final seconds = entry.lastPositionSeconds;
    final progress = seconds >= 60 ? '${seconds ~/ 60} 分钟' : '${seconds}s';
    if (target?.index != null && (target?.index ?? -1) >= 0) {
      return '继续播放 第 ${(target!.index) + 1} 集';
    }
    return '继续播放 · $progress';
  }

  String _resumeSummaryText(PlaybackHistoryItem entry, _ResumeTarget? target) {
    final seconds = entry.lastPositionSeconds;
    final progress = seconds >= 60 ? '${seconds ~/ 60} 分钟' : '${seconds}s';
    if (target != null && target.index >= 0) {
      return '上次看到第 ${target.index + 1} 集，已观看 $progress';
    }
    return '上次播放停在 $progress，可直接继续观看';
  }

  String _sourceName(AppController app, String sourceId) {
    for (final s in app.sources) {
      if (s.id == sourceId) return s.name;
    }
    return sourceId;
  }

  List<_EpisodeEntry> _visibleEpisodes(AppController app, VideoItem detail) {
    final entries = <_EpisodeEntry>[
      for (var i = 0; i < _episodes.length; i++)
        _EpisodeEntry(
          episode: _episodes[i],
          originalIndex: i,
          history: app.findHistoryForVideo(
            _episodePlayableItem(detail, _episodes[i]),
          ),
        ),
    ];

    var filtered = [...entries];

    switch (_episodeStatusFilter) {
      case _EpisodeStatusFilter.all:
        break;
      case _EpisodeStatusFilter.inProgress:
        filtered = filtered
            .where((entry) => (entry.history?.lastPositionSeconds ?? 0) > 0)
            .toList();
        break;
      case _EpisodeStatusFilter.unwatched:
        filtered = filtered.where((entry) => entry.history == null).toList();
        break;
    }

    if (_episodeQuery.isNotEmpty) {
      final query = _episodeQuery.toLowerCase();
      final number = int.tryParse(query);
      filtered = filtered.where((entry) {
        if (number != null && entry.originalIndex + 1 == number) return true;
        return entry.episode.name.toLowerCase().contains(query);
      }).toList();
    }

    if (_episodeSortMode == _EpisodeSortMode.recentWatched) {
      filtered.sort((a, b) {
        final aw = a.history?.watchedAt;
        final bw = b.history?.watchedAt;
        if (aw == null && bw == null) {
          return a.originalIndex.compareTo(b.originalIndex);
        }
        if (aw == null) return 1;
        if (bw == null) return -1;
        return bw.compareTo(aw);
      });
      return filtered;
    }

    return filtered;
  }

  VideoItem _episodePlayableItem(VideoItem detail, EpisodeItem episode) {
    return VideoItem(
      id: detail.id,
      title: '${detail.title} ${episode.name}',
      description: detail.description,
      poster: detail.poster,
      url: episode.url,
      sourceId: detail.sourceId,
      vodPlayUrl: detail.vodPlayUrl,
    );
  }

  String _episodeStatusText(PlaybackHistoryItem? entry) {
    if (entry == null) return '未播放';
    final seconds = entry.lastPositionSeconds;
    if (seconds <= 0) return '刚开始';
    return seconds >= 60 ? '已看 ${seconds ~/ 60} 分钟' : '已看 ${seconds}s';
  }

  List<_EpisodeSummaryStat> _episodeSummaryStats(
    AppController app,
    VideoItem detail,
  ) {
    var inProgress = 0;
    var started = 0;
    var untouched = 0;

    for (final episode in _episodes) {
      final history = app.findHistoryForVideo(
        _episodePlayableItem(detail, episode),
      );
      if (history == null) {
        untouched += 1;
        continue;
      }
      started += 1;
      if (history.lastPositionSeconds > 0) {
        inProgress += 1;
      }
    }

    return [
      _EpisodeSummaryStat(
        label: '进行中',
        value: '$inProgress',
        emphasize: inProgress > 0,
      ),
      _EpisodeSummaryStat(label: '已开始', value: '$started'),
      _EpisodeSummaryStat(label: '未播放', value: '$untouched'),
    ];
  }

  List<_EpisodeOverviewData> _episodeOverviewBadges({
    required PlaybackHistoryItem? resumeEntry,
    required _ResumeTarget? resumeTarget,
    required _EpisodeEntry? nextUnwatched,
    required List<_EpisodeSummaryStat> episodeStats,
  }) {
    final badges = <_EpisodeOverviewData>[
      _EpisodeOverviewData(
        icon: Icons.video_library_outlined,
        text: _episodes.isEmpty ? '单条资源' : '共 ${_episodes.length} 集',
      ),
    ];

    final inProgress = episodeStats.firstWhere(
      (stat) => stat.label == '进行中',
      orElse: () => const _EpisodeSummaryStat(label: '进行中', value: '0'),
    );
    if (int.tryParse(inProgress.value) case final value? when value > 0) {
      badges.add(
        _EpisodeOverviewData(
          icon: Icons.timelapse_rounded,
          text: '${inProgress.value} 集在追',
          emphasize: true,
        ),
      );
    }

    if (resumeEntry != null &&
        resumeTarget != null &&
        resumeTarget.index >= 0) {
      badges.add(
        _EpisodeOverviewData(
          icon: Icons.play_circle_fill_rounded,
          text: '续播到第 ${resumeTarget.index + 1} 集',
          emphasize: true,
        ),
      );
    } else if (nextUnwatched != null) {
      badges.add(
        _EpisodeOverviewData(
          icon: Icons.skip_next_rounded,
          text: '推荐看第 ${nextUnwatched.originalIndex + 1} 集',
        ),
      );
    }

    return badges;
  }

  List<_EpisodeMarkerData> _episodeMarkers(
    _EpisodeEntry entry, {
    required _ResumeTarget? resumeTarget,
    required _EpisodeEntry? nextUnwatched,
  }) {
    final markers = <_EpisodeMarkerData>[];
    if ((resumeTarget?.index ?? -1) == entry.originalIndex) {
      markers.add(
        const _EpisodeMarkerData(
          text: '继续这里',
          icon: Icons.play_circle_fill_rounded,
          emphasize: true,
        ),
      );
    }
    if ((nextUnwatched?.originalIndex ?? -1) == entry.originalIndex) {
      markers.add(
        const _EpisodeMarkerData(text: '下一集', icon: Icons.skip_next_rounded),
      );
    }
    if (entry.history != null) {
      markers.add(
        _EpisodeMarkerData(
          text: '最近看过 ${_formatRelativeWatchTime(entry.history!.watchedAt)}',
          icon: Icons.history_rounded,
        ),
      );
    }
    return markers;
  }

  String _episodeActionLabel(
    _EpisodeEntry entry, {
    required _ResumeTarget? resumeTarget,
    required _EpisodeEntry? nextUnwatched,
  }) {
    if ((resumeTarget?.index ?? -1) == entry.originalIndex) {
      return '继续播放';
    }
    if ((nextUnwatched?.originalIndex ?? -1) == entry.originalIndex) {
      return '播放下一集';
    }
    return '播放本集';
  }

  double? _episodeProgressValue(PlaybackHistoryItem? entry) {
    if (entry == null || entry.lastPositionSeconds <= 0) return null;
    const baselineSeconds = 45 * 60;
    return (entry.lastPositionSeconds / baselineSeconds).clamp(0.0, 1.0);
  }

  String _formatRelativeWatchTime(DateTime watchedAt) {
    final diff = DateTime.now().difference(watchedAt.toLocal());
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
    if (diff.inDays < 1) return '${diff.inHours} 小时前';
    if (diff.inDays < 7) return '${diff.inDays} 天前';
    return '${watchedAt.month}-${watchedAt.day}';
  }

  _EpisodeEntry? _findNextUnwatchedEpisode(
    AppController app,
    VideoItem detail,
  ) {
    for (var i = 0; i < _episodes.length; i++) {
      final episode = _episodes[i];
      final history = app.findHistoryForVideo(
        _episodePlayableItem(detail, episode),
      );
      if (history == null || history.lastPositionSeconds <= 0) {
        return _EpisodeEntry(
          episode: episode,
          originalIndex: i,
          history: history,
        );
      }
    }
    return null;
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
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('输入的集数无效')));
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
    required this.history,
  });

  final EpisodeItem episode;
  final int originalIndex;
  final PlaybackHistoryItem? history;
}

class _ResumeTarget {
  const _ResumeTarget({required this.episode, required this.index});

  final EpisodeItem? episode;
  final int index;
}

class _EpisodeMarkerData {
  const _EpisodeMarkerData({
    required this.text,
    required this.icon,
    this.emphasize = false,
  });

  final String text;
  final IconData icon;
  final bool emphasize;
}

class _EpisodeOverviewData {
  const _EpisodeOverviewData({
    required this.icon,
    required this.text,
    this.emphasize = false,
  });

  final IconData icon;
  final String text;
  final bool emphasize;
}

class _EpisodeSummaryStat {
  const _EpisodeSummaryStat({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;
}

class _EpisodeGridCard extends StatelessWidget {
  const _EpisodeGridCard({
    required this.title,
    required this.imageUrl,
    required this.subtitle,
    required this.statusText,
    required this.markers,
    required this.onPlay,
    required this.actionLabel,
    this.progressValue,
    this.highlight = false,
  });

  final String title;
  final String imageUrl;
  final String subtitle;
  final String statusText;
  final List<_EpisodeMarkerData> markers;
  final VoidCallback onPlay;
  final String actionLabel;
  final double? progressValue;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: highlight
          ? Theme.of(
              context,
            ).colorScheme.primaryContainer.withValues(alpha: 0.45)
          : null,
      clipBehavior: Clip.antiAlias,
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
            Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 6),
            Text(
              statusText,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (markers.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: markers.map((marker) {
                  return _EpisodeMarkerChip(marker: marker);
                }).toList(),
              ),
            ],
            if (progressValue != null) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  minHeight: 6,
                  value: progressValue,
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest,
                ),
              ),
            ],
            const SizedBox(height: 6),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onPlay,
                icon: const Icon(Icons.play_arrow, size: 16),
                label: Text(actionLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EpisodeSummaryChip extends StatelessWidget {
  const _EpisodeSummaryChip({required this.stat});

  final _EpisodeSummaryStat stat;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: stat.emphasize
            ? scheme.primary.withValues(alpha: 0.12)
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: RichText(
        text: TextSpan(
          style: Theme.of(context).textTheme.bodySmall,
          children: [
            TextSpan(
              text: '${stat.value} ',
              style: TextStyle(
                color: stat.emphasize ? scheme.primary : scheme.onSurface,
                fontWeight: FontWeight.w800,
              ),
            ),
            TextSpan(
              text: stat.label,
              style: TextStyle(
                color: stat.emphasize
                    ? scheme.primary
                    : scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EpisodeOverviewBadge extends StatelessWidget {
  const _EpisodeOverviewBadge({required this.badge});

  final _EpisodeOverviewData badge;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: badge.emphasize
            ? Colors.white.withValues(alpha: 0.2)
            : Colors.black.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: Colors.white.withValues(alpha: badge.emphasize ? 0.28 : 0.12),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            badge.icon,
            size: 14,
            color: badge.emphasize ? Colors.white : Colors.white70,
          ),
          const SizedBox(width: 5),
          Text(
            badge.text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: badge.emphasize ? Colors.white : Colors.white70,
              fontWeight: badge.emphasize ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _EpisodeMarkerChip extends StatelessWidget {
  const _EpisodeMarkerChip({required this.marker});

  final _EpisodeMarkerData marker;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: marker.emphasize
            ? scheme.primary.withValues(alpha: 0.14)
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            marker.icon,
            size: 14,
            color: marker.emphasize ? scheme.primary : scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Text(
            marker.text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: marker.emphasize
                  ? scheme.primary
                  : scheme.onSurfaceVariant,
              fontWeight: marker.emphasize ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
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

enum _EpisodeStatusFilter {
  all('全部'),
  inProgress('有进度'),
  unwatched('未播放');

  const _EpisodeStatusFilter(this.label);

  final String label;
}

enum _EpisodeSortMode { episodeOrder, recentWatched }
