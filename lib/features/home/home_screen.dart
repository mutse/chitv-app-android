import 'dart:async';
import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app/app_scope.dart';
import '../../app/app_theme.dart';
import '../../core/models/douban_item.dart';
import '../../core/models/playback_history_item.dart';
import '../../core/models/video_item.dart';
import '../detail/detail_screen.dart';
import '../player/player_screen.dart';
import '../settings/settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const double _bottomNavHeight = 80;
  static const double _bottomNavOuterMargin = 12;
  static const double _bottomContentSpacing = 20;
  final _controller = TextEditingController();
  int _tab = 0;
  int _featuredIndex = 0;
  Set<String> _selectedSourceIds = <String>{};
  Set<String> _lastEnabledSourceIds = <String>{};
  bool _sourceSelectionInitialized = false;
  bool _refreshQueued = false;
  int _handledSourceMutationVersion = 0;
  int _handledContentMutationVersion = 0;
  int _handledHomeDisplayMutationVersion = 0;
  Timer? _searchDebounce;
  double _largeTitleProgress = 1;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final isHomeTab = _tab == 0;
    _syncSelectedSources(app);

    if (app.initializing) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      extendBody: true,
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface.withValues(
          alpha: 0.58 + ((1 - _largeTitleProgress) * 0.3),
        ),
        surfaceTintColor: Colors.transparent,
        toolbarHeight: 56,
        title: ChiTvNavTitle(title: isHomeTab ? 'ChiTV' : _tabTitle(_tab)),
        bottom: isHomeTab
            ? PreferredSize(
                preferredSize: Size.fromHeight(_largeTitleHeight),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  height: _largeTitleHeight,
                  alignment: Alignment.bottomLeft,
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: Theme.of(context).colorScheme.outlineVariant
                            .withValues(
                              alpha: 0.12 + ((1 - _largeTitleProgress) * 0.26),
                            ),
                      ),
                    ),
                  ),
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 120),
                    opacity: _largeTitleProgress.clamp(0.0, 1.0),
                    child: ChiTvLargeNavHeader(
                      title: _tabTitle(_tab),
                      subtitle: _tabLargeSubtitle(_tab),
                      progress: _largeTitleProgress,
                    ),
                  ),
                ),
              )
            : null,
      ),
      body: ChiTvBackground(
        child: NotificationListener<ScrollNotification>(
          onNotification: _handleScrollNotification,
          child: switch (_tab) {
            0 => _buildHomeTab(context),
            1 => _buildSearchTab(context),
            2 => _buildFavoritesTab(context),
            _ => const SettingsScreen(),
          },
        ),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (v) {
              setState(() {
                _tab = v;
                _largeTitleProgress = 1;
              });
            },
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_rounded),
                label: '首页',
              ),
              NavigationDestination(icon: Icon(Icons.search), label: '搜索'),
              NavigationDestination(icon: Icon(Icons.favorite), label: '收藏'),
              NavigationDestination(icon: Icon(Icons.settings), label: '设置'),
            ],
          ),
        ),
      ),
    );
  }

  double get _largeTitleHeight =>
      _tab == 0 ? (lerpDouble(0, 44, _largeTitleProgress) ?? 44) : 0;
  double get _rootTopInset =>
      _tab == 0 ? (lerpDouble(4, 8, _largeTitleProgress) ?? 8) : 4;

  double _bottomContentInset(BuildContext context) {
    return MediaQuery.of(context).padding.bottom +
        _bottomNavHeight +
        _bottomNavOuterMargin +
        _bottomContentSpacing;
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical || notification.depth != 0) {
      return false;
    }
    final offset = notification.metrics.pixels.clamp(0.0, 72.0);
    final next = (1 - (offset / 72)).clamp(0.0, 1.0);
    if ((next - _largeTitleProgress).abs() < 0.02) {
      return false;
    }
    setState(() => _largeTitleProgress = next);
    return false;
  }

  String _tabTitle(int tab) {
    return switch (tab) {
      1 => '搜索',
      2 => '收藏',
      3 => '设置',
      _ => '首页',
    };
  }

  String _tabLargeSubtitle(int tab) {
    return '';
  }

  Widget _buildHomeTab(BuildContext context) {
    final app = AppScope.of(context);
    return Column(
      children: [
        if (app.error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(app.error!, style: const TextStyle(color: Colors.red)),
          ),
        Expanded(child: _buildHomeFeed(context, app)),
      ],
    );
  }

  Widget _buildSearchTab(BuildContext context) {
    final app = AppScope.of(context);

    final query = _controller.text.trim();
    final showSearchResults = query.isNotEmpty;

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(12, _rootTopInset, 12, 12),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '搜索你想看的内容',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '参考 iOS 版独立搜索页，聚合搜索和最近搜索都单独展示。',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          decoration: InputDecoration(
                            hintText: '搜索你喜欢的视频',
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: query.isEmpty
                                ? null
                                : IconButton(
                                    icon: const Icon(Icons.clear),
                                    onPressed: () {
                                      _controller.clear();
                                      app.clearSearchState();
                                      setState(() {});
                                    },
                                  ),
                          ),
                          onChanged: (_) => _onQueryChanged(app),
                          onSubmitted: (_) => _doSearch(app),
                        ),
                      ),
                      const SizedBox(width: 10),
                      FilledButton(
                        onPressed: app.searching ? null : () => _doSearch(app),
                        child: app.searching
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('搜索'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        _buildSourceFilterBar(app),
        if (!showSearchResults && app.recentSearches.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '最近搜索',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '点一下即可再次搜索你最近看过的关键词。',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ...app.recentSearches.take(8).map((text) {
                          return ActionChip(
                            avatar: const Icon(Icons.history, size: 16),
                            label: Text(text),
                            onPressed: () {
                              _controller.text = text;
                              setState(() {});
                              _doSearch(app);
                            },
                          );
                        }),
                        ActionChip(
                          avatar: const Icon(Icons.delete_outline, size: 18),
                          label: const Text('清空历史'),
                          onPressed: app.clearSearchHistory,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (app.error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(app.error!, style: const TextStyle(color: Colors.red)),
          ),
        Expanded(
          child: query.isNotEmpty
              ? _buildSearchResultList(app)
              : _buildSearchIdleState(context, app),
        ),
      ],
    );
  }

  Widget _buildSearchIdleState(BuildContext context, AppController app) {
    if (app.searching) {
      return const Center(child: CircularProgressIndicator());
    }

    return _buildLibraryEmptyState(
      context,
      icon: Icons.manage_search_rounded,
      title: '开始搜索影片',
      subtitle: app.recentSearches.isNotEmpty
          ? '输入关键词，或者直接点上方最近搜索快速继续查找。'
          : '输入片名、演员或关键词后，我们会从当前片源里聚合搜索结果。',
    );
  }

  Widget _buildSearchResultList(AppController app) {
    final list = app.searchResults;
    if (app.searching) {
      return const Center(child: CircularProgressIndicator());
    }
    if (list.isEmpty) {
      return _buildLibraryEmptyState(
        context,
        icon: Icons.search_off_rounded,
        title: '没有找到匹配结果',
        subtitle: '试试更短的关键词，或者切换不同视频源后再搜索。',
      );
    }

    return ListView(
      padding: EdgeInsets.fromLTRB(12, _rootTopInset, 12, 28),
      children: [
        _LibraryHeroCard(
          title: '搜索结果',
          subtitle: '已按当前启用的视频源聚合展示相关内容。',
          leadingIcon: Icons.travel_explore_rounded,
          stats: [
            _LibraryStat(label: '结果', value: '${list.length}'),
            _LibraryStat(
              label: '视频源',
              value: '${list.map((item) => item.sourceId).toSet().length}',
            ),
            _LibraryStat(
              label: '收藏',
              value: '${list.where((item) => app.isFavorite(item.id)).length}',
            ),
          ],
        ),
        const _SectionHeader(title: '匹配内容', subtitle: '挑选结果后可继续查看详情或直接播放'),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          itemCount: list.length,
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 240,
            mainAxisExtent: 320,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemBuilder: (context, index) {
            final item = list[index];
            return _VideoGridCard(
              item: item,
              badgeText: _sourceLabel(app, item.sourceId),
              watchStatusText: _watchStatusText(app.findHistoryForVideo(item)),
              isFavorite: app.isFavorite(item.id),
              onFavoriteToggle: () => app.toggleFavorite(item),
              onPlay: () => _playOrResume(context, item),
              onDetail: () => _openDetail(context, item),
            );
          },
        ),
      ],
    );
  }

  Widget _buildSourceFilterBar(AppController app) {
    final enabled = app.sources.where((s) => s.enabled).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '片源过滤',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                '控制搜索和首页推荐使用哪些数据源。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 46,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        selected: _selectedSourceIds.length == enabled.length,
                        label: const Text('全部'),
                        onSelected: (_) {
                          _applySourceSelection(
                            app,
                            enabled.map((e) => e.id).toSet(),
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        selected: _selectedSourceIds.isEmpty,
                        label: const Text('无'),
                        onSelected: (_) {
                          _applySourceSelection(app, <String>{});
                        },
                      ),
                    ),
                    ...enabled.map((s) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          selected: _selectedSourceIds.contains(s.id),
                          avatar: Icon(
                            Icons.cloud_outlined,
                            size: 16,
                            color: _selectedSourceIds.contains(s.id)
                                ? Colors.white
                                : Theme.of(context).colorScheme.primary,
                          ),
                          label: Text(s.name),
                          onSelected: (selected) {
                            final nextSelected = {..._selectedSourceIds};
                            if (selected) {
                              nextSelected.add(s.id);
                            } else {
                              nextSelected.remove(s.id);
                            }
                            _applySourceSelection(app, nextSelected);
                          },
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDoubanHotSection(BuildContext context, AppController app) {
    final hasMovies = app.doubanHotMovies.isNotEmpty;
    final hasTv = app.doubanHotTvShows.isNotEmpty;
    if (app.loadingDoubanHot && !hasMovies && !hasTv) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(12, 6, 12, 2),
        child: LinearProgressIndicator(minHeight: 2),
      );
    }
    if (!hasMovies && !hasTv) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(title: '豆瓣热门', subtitle: '点选任意条目即可快速发起搜索'),
        if (hasMovies) _buildDoubanStrip(context, '电影', app.doubanHotMovies),
        if (hasTv) _buildDoubanStrip(context, '剧集', app.doubanHotTvShows),
      ],
    );
  }

  Widget _buildDoubanStrip(
    BuildContext context,
    String label,
    List<DoubanItem> items,
  ) {
    return SizedBox(
      height: 132,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: SizedBox(
              width: 112,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          label == '电影'
                              ? Icons.movie_creation_outlined
                              : Icons.tv_outlined,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        label,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '热门推荐',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          ...items.take(10).map((item) {
            return Padding(
              padding: const EdgeInsets.only(right: 12),
              child: SizedBox(
                width: 190,
                child: Card(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () {
                      final app = AppScope.read(context);
                      _controller.text = item.title;
                      setState(() {});
                      _doSearch(app);
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  label,
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const Spacer(),
                              if (item.rate > 0)
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.star_rounded,
                                      size: 14,
                                      color: Colors.amber,
                                    ),
                                    const SizedBox(width: 2),
                                    Text(
                                      item.rate.toStringAsFixed(1),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                          const Spacer(),
                          Text(
                            item.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '点按即可搜索相关资源',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildHomeFeed(BuildContext context, AppController app) {
    if (app.loadingHome) {
      return const Center(child: CircularProgressIndicator());
    }
    if (app.homeVideos.isEmpty) {
      return _buildLibraryEmptyState(
        context,
        icon: Icons.live_tv_rounded,
        title: '暂无首页内容',
        subtitle: '请检查视频源配置，或稍后刷新首页推荐。',
      );
    }

    final featured = app.homeVideos.take(5).toList();
    final others = app.homeVideos.skip(featured.length).toList();

    return RefreshIndicator(
      onRefresh: () async {
        await app.loadHomeVideos(sourceIds: _selectedSourceIds);
        await app.loadDoubanHot();
      },
      child: ListView(
        padding: EdgeInsets.only(
          top: _rootTopInset,
          bottom: _bottomContentInset(context),
        ),
        children: [
          _buildDoubanHotSection(context, app),
          if (app.history.isNotEmpty) ...[
            const _SectionHeader(title: '继续观看', subtitle: '回到上次离开的地方'),
            SizedBox(
              height: 188,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: app.history.take(8).map((entry) {
                  final item = entry.video;
                  return Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: SizedBox(
                      width: 220,
                      child: Card(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: () => _resumeHistoryEntry(context, entry),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary
                                            .withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                      ),
                                      child: Text(
                                        '继续观看',
                                        style: TextStyle(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.primary,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const Spacer(),
                                Text(
                                  item.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '已看 ${_formatPlaybackProgress(entry.lastPositionSeconds)}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '观看于 ${_formatDateTime(entry.watchedAt)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                const SizedBox(height: 10),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(999),
                                  child: LinearProgressIndicator(
                                    minHeight: 6,
                                    value: _watchProgressValue(
                                      entry.lastPositionSeconds,
                                    ),
                                    backgroundColor: Theme.of(
                                      context,
                                    ).colorScheme.surfaceContainerHighest,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: FilledButton.tonal(
                                        onPressed: () => _playVideo(
                                          context,
                                          item,
                                          initialPositionSeconds: 0,
                                        ),
                                        child: const Text('从头看'),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: FilledButton(
                                        onPressed: () =>
                                            _resumeHistoryEntry(context, entry),
                                        child: const Text('继续播'),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
          if (featured.isNotEmpty) ...[
            const _SectionHeader(title: '精选推荐', subtitle: '参考 iOS 版的沉浸式海报展示'),
            SizedBox(
              height: 260,
              child: PageView.builder(
                itemCount: featured.length,
                onPageChanged: (index) =>
                    setState(() => _featuredIndex = index),
                itemBuilder: (context, index) {
                  final item = featured[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          item.poster.isEmpty
                              ? Container(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.surfaceContainer,
                                )
                              : Image.network(
                                  item.poster,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
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
                            left: 14,
                            right: 14,
                            bottom: 14,
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        item.title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 20,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        _sourceLabel(app, item.sourceId),
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: Colors.black,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 14,
                                    ),
                                  ),
                                  onPressed: () => _playOrResume(context, item),
                                  icon: const Icon(Icons.play_arrow),
                                  label: const Text(''),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            if (featured.length > 1)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List<Widget>.generate(featured.length, (index) {
                    final selected = index == _featuredIndex;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: selected ? 20 : 8,
                      height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: selected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    );
                  }),
                ),
              ),
          ],
          const _SectionHeader(title: '更多视频', subtitle: '继续探索其他推荐内容'),
          if (others.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text('暂无更多内容'),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: others.length,
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 240,
                mainAxisExtent: 300,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemBuilder: (context, index) {
                final item = others[index];
                return _VideoGridCard(
                  item: item,
                  watchStatusText: _watchStatusText(
                    app.findHistoryForVideo(item),
                  ),
                  isFavorite: app.isFavorite(item.id),
                  onFavoriteToggle: () => app.toggleFavorite(item),
                  onPlay: () => _playOrResume(context, item),
                  onDetail: () => _openDetail(context, item),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildFavoritesTab(BuildContext context) {
    final app = AppScope.of(context);
    if (app.favorites.isEmpty) {
      return _buildLibraryEmptyState(
        context,
        icon: Icons.favorite_border_rounded,
        title: '还没有收藏内容',
        subtitle: '把喜欢的视频加入收藏后，这里会成为你的专属片单。',
      );
    }

    final sources = app.favorites.map((entry) => entry.sourceId).toSet().length;
    final titled = app.favorites.where((item) => item.title.isNotEmpty).length;

    return ListView(
      padding: EdgeInsets.fromLTRB(
        12,
        _rootTopInset,
        12,
        _bottomContentInset(context),
      ),
      children: [
        _LibraryHeroCard(
          title: '我的收藏',
          subtitle: '用更轻的 iOS 风格卡片整理你最想继续追的内容。',
          leadingIcon: Icons.favorite_rounded,
          stats: [
            _LibraryStat(label: '收藏', value: '${app.favorites.length}'),
            _LibraryStat(label: '来源', value: '$sources'),
            _LibraryStat(label: '已命名', value: '$titled'),
          ],
        ),
        const _SectionHeader(title: '精选片单', subtitle: '优先展示你已收藏的内容'),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          itemCount: app.favorites.length,
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 240,
            mainAxisExtent: 320,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemBuilder: (context, index) {
            final item = app.favorites[index];
            return _VideoGridCard(
              item: item,
              badgeText: '已收藏',
              watchStatusText: _watchStatusText(app.findHistoryForVideo(item)),
              isFavorite: true,
              onFavoriteToggle: () => app.toggleFavorite(item),
              onPlay: () => _playOrResume(context, item),
              onDetail: () => _openDetail(context, item),
            );
          },
        ),
        const SizedBox(height: 4),
        const _LibraryFooterNote(text: '收藏会同步保存在本地，方便你随时继续浏览或播放。'),
      ],
    );
  }

  Widget _buildLibraryEmptyState(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Icon(
                    icon,
                    size: 34,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openDetail(BuildContext context, VideoItem item) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => DetailScreen(item: item)));
  }

  void _resumeHistoryEntry(BuildContext context, PlaybackHistoryItem entry) {
    _playVideo(
      context,
      entry.video,
      initialPositionSeconds: entry.lastPositionSeconds,
    );
  }

  void _playOrResume(BuildContext context, VideoItem item) {
    final historyEntry = AppScope.read(context).findHistoryForVideo(item);
    if (historyEntry != null && historyEntry.lastPositionSeconds > 0) {
      _resumeHistoryEntry(context, historyEntry);
      return;
    }
    _playVideo(context, item);
  }

  void _playVideo(
    BuildContext context,
    VideoItem item, {
    int initialPositionSeconds = 0,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlayerScreen(
          item: item,
          initialPositionSeconds: initialPositionSeconds,
        ),
      ),
    );
  }

  void _syncSelectedSources(AppController app) {
    final enabled = app.sources
        .where((s) => s.enabled)
        .map((e) => e.id)
        .toSet();
    if (!_sourceSelectionInitialized) {
      _selectedSourceIds = enabled;
      _lastEnabledSourceIds = enabled;
      _sourceSelectionInitialized = true;
      _handledSourceMutationVersion = app.sourceMutationVersion;
      _handledContentMutationVersion = app.contentMutationVersion;
      _handledHomeDisplayMutationVersion = app.homeDisplayMutationVersion;
      return;
    }

    final hadAllEnabledSelected = setEquals(
      _selectedSourceIds,
      _lastEnabledSourceIds,
    );
    final refreshRequest = _consumeRefreshRequest(
      app,
      enabled: enabled,
      hadAllEnabledSelected: hadAllEnabledSelected,
    );

    _selectedSourceIds = refreshRequest.selectedSourceIds;
    _lastEnabledSourceIds = enabled;

    if (refreshRequest.shouldRefresh) {
      _queueContentRefresh(
        app,
        refreshDoubanHot: refreshRequest.refreshDoubanHot,
      );
    }
  }

  void _onQueryChanged(AppController app) {
    setState(() {});
    _searchDebounce?.cancel();
    if (_controller.text.trim().isEmpty) {
      app.clearSearchState();
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 320), () {
      if (!mounted) return;
      _doSearch(app);
    });
  }

  void _doSearch(AppController app) {
    final query = _controller.text.trim();
    if (query.isEmpty) {
      app.clearSearchState();
      return;
    }
    app.search(query, sourceIds: _selectedSourceIds);
  }

  void _applySourceSelection(AppController app, Set<String> nextSelected) {
    if (setEquals(_selectedSourceIds, nextSelected)) {
      return;
    }
    setState(() {
      _selectedSourceIds = nextSelected;
    });
    _queueContentRefresh(app);
  }

  void _queueContentRefresh(
    AppController app, {
    bool refreshDoubanHot = false,
  }) {
    if (_refreshQueued) return;
    _refreshQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _refreshQueued = false;
      if (!mounted) return;
      await app.loadHomeVideos(sourceIds: _selectedSourceIds);
      if (refreshDoubanHot) {
        await app.loadDoubanHot(silent: true);
      }
      final query = _controller.text.trim();
      if (query.isNotEmpty) {
        await app.search(query, sourceIds: _selectedSourceIds);
      }
    });
  }

  _HomeRefreshRequest _consumeRefreshRequest(
    AppController app, {
    required Set<String> enabled,
    required bool hadAllEnabledSelected,
  }) {
    final nextSelected = hadAllEnabledSelected
        ? enabled
        : _selectedSourceIds.intersection(enabled);
    final sourceMutationChanged =
        app.sourceMutationVersion != _handledSourceMutationVersion;
    final contentMutationChanged =
        app.contentMutationVersion != _handledContentMutationVersion;
    final homeDisplayMutationChanged =
        app.homeDisplayMutationVersion != _handledHomeDisplayMutationVersion;

    _handledSourceMutationVersion = app.sourceMutationVersion;
    _handledContentMutationVersion = app.contentMutationVersion;
    _handledHomeDisplayMutationVersion = app.homeDisplayMutationVersion;

    return _HomeRefreshRequest(
      selectedSourceIds: nextSelected,
      shouldRefresh:
          sourceMutationChanged ||
          contentMutationChanged ||
          homeDisplayMutationChanged,
      refreshDoubanHot: homeDisplayMutationChanged,
    );
  }

  String _formatDateTime(DateTime dt) {
    final local = dt.toLocal();
    final mm = local.month.toString().padLeft(2, '0');
    final dd = local.day.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '$mm-$dd $hh:$min';
  }

  String _formatPlaybackProgress(int seconds) {
    if (seconds <= 0) return '不到 1 秒';
    if (seconds < 60) return '${seconds}s';
    final minutes = seconds ~/ 60;
    if (minutes < 60) return '$minutes 分钟';
    final hours = minutes ~/ 60;
    final remainMinutes = minutes % 60;
    if (remainMinutes == 0) return '$hours 小时';
    return '$hours 小时 $remainMinutes 分钟';
  }

  double _watchProgressValue(int seconds) {
    const baselineSeconds = 45 * 60;
    if (seconds <= 0) return 0;
    return (seconds / baselineSeconds).clamp(0.0, 1.0);
  }

  String? _watchStatusText(PlaybackHistoryItem? entry) {
    if (entry == null) return null;
    final seconds = entry.lastPositionSeconds;
    if (seconds <= 0) return '刚开始';
    return '已看 ${_formatPlaybackProgress(seconds)}';
  }

  String _sourceLabel(AppController app, String sourceId) {
    for (final source in app.sources) {
      if (source.id == sourceId) {
        return source.name;
      }
    }
    return sourceId;
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _HomeRefreshRequest {
  const _HomeRefreshRequest({
    required this.selectedSourceIds,
    required this.shouldRefresh,
    required this.refreshDoubanHot,
  });

  final Set<String> selectedSourceIds;
  final bool shouldRefresh;
  final bool refreshDoubanHot;
}

class _LibraryHeroCard extends StatelessWidget {
  const _LibraryHeroCard({
    required this.title,
    required this.subtitle,
    required this.leadingIcon,
    required this.stats,
  });

  final String title;
  final String subtitle;
  final IconData leadingIcon;
  final List<_LibraryStat> stats;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    leadingIcon,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: stats
                  .map((stat) => _LibraryStatChip(stat: stat))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _LibraryStat {
  const _LibraryStat({required this.label, required this.value});

  final String label;
  final String value;
}

class _LibraryStatChip extends StatelessWidget {
  const _LibraryStatChip({required this.stat});

  final _LibraryStat stat;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(16),
      ),
      child: RichText(
        text: TextSpan(
          style: Theme.of(context).textTheme.bodySmall,
          children: [
            TextSpan(
              text: '${stat.value} ',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            TextSpan(
              text: stat.label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LibraryFooterNote extends StatelessWidget {
  const _LibraryFooterNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
      child: Text(text, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}

class _VideoGridCard extends StatelessWidget {
  const _VideoGridCard({
    required this.item,
    required this.isFavorite,
    required this.onFavoriteToggle,
    required this.onPlay,
    required this.onDetail,
    this.badgeText,
    this.watchStatusText,
  });

  final VideoItem item;
  final bool isFavorite;
  final VoidCallback onFavoriteToggle;
  final VoidCallback onPlay;
  final VoidCallback onDetail;
  final String? badgeText;
  final String? watchStatusText;

  @override
  Widget build(BuildContext context) {
    final extra = context.chitvTheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                item.poster.isEmpty
                    ? Container(
                        color: Theme.of(context).colorScheme.surfaceContainer,
                      )
                    : Image.network(
                        item.poster,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: Theme.of(context).colorScheme.surfaceContainer,
                        ),
                      ),
                Positioned(
                  left: 10,
                  top: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: extra.overlayPanel,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      badgeText ?? item.sourceId,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 8,
                  top: 8,
                  child: IconButton.filledTonal(
                    onPressed: onFavoriteToggle,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black45,
                      foregroundColor: Colors.white,
                    ),
                    icon: Icon(
                      isFavorite ? Icons.favorite : Icons.favorite_border,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (watchStatusText != null) ...[
                  Text(
                    watchStatusText!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                Text(
                  item.description.isEmpty ? '暂无简介' : item.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onPlay,
                    icon: const Icon(Icons.play_arrow, size: 16),
                    label: const Text(''),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onDetail,
                    icon: const Icon(Icons.list, size: 16),
                    label: const Text(''),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
