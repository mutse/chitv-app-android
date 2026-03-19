import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app/app_scope.dart';
import '../../app/app_theme.dart';
import '../../core/models/douban_item.dart';
import '../../core/models/playback_history_item.dart';
import '../../core/models/video_item.dart';
import '../detail/detail_screen.dart';
import '../settings/settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _controller = TextEditingController();
  int _tab = 0;
  int _featuredIndex = 0;
  Set<String> _selectedSourceIds = <String>{};
  bool _sourceSelectionInitialized = false;
  Timer? _searchDebounce;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    _syncSelectedSources(app);

    if (app.initializing) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      extendBody: true,
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.all(6),
              child: Image.asset('assets/icon.png'),
            ),
            const SizedBox(width: 12),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('ChiTV'),
                SizedBox(height: 2),
                Text(
                  'Android',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ],
        ),
        actions: [
          if (_tab == 0)
            IconButton(
              onPressed: () async {
                await app.loadHomeVideos(sourceIds: _selectedSourceIds);
                await app.loadDoubanHot();
              },
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
      body: ChiTvBackground(
        child: switch (_tab) {
          0 => _buildSearchTab(context),
          1 => _buildHistoryTab(context),
          2 => _buildFavoritesTab(context),
          _ => const SettingsScreen(),
        },
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (v) => setState(() => _tab = v),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.search), label: '首页/搜索'),
              NavigationDestination(icon: Icon(Icons.history), label: '历史'),
              NavigationDestination(icon: Icon(Icons.favorite), label: '收藏'),
              NavigationDestination(icon: Icon(Icons.settings), label: '设置'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchTab(BuildContext context) {
    final app = AppScope.of(context);

    final query = _controller.text.trim();
    final showSearchResults = query.isNotEmpty;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '发现你想看的内容',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '聚合搜索、热门推荐和继续观看都集中在这里。',
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
                                      setState(() {});
                                      app.loadHomeVideos(sourceIds: _selectedSourceIds);
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
                                child: CircularProgressIndicator(strokeWidth: 2),
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
          child: showSearchResults
              ? _buildSearchResultList(app)
              : _buildHomeFeed(context, app),
        ),
      ],
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
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 28),
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
              isFavorite: app.isFavorite(item.id),
              onFavoriteToggle: () => app.toggleFavorite(item),
              onPlay: () => _openDetail(context, item),
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
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
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
                          setState(() {
                            _selectedSourceIds = enabled.map((e) => e.id).toSet();
                          });
                          _doSearch(app);
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        selected: _selectedSourceIds.isEmpty,
                        label: const Text('无'),
                        onSelected: (_) {
                          setState(() {
                            _selectedSourceIds = <String>{};
                          });
                          _doSearch(app);
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
                            setState(() {
                              if (selected) {
                                _selectedSourceIds.add(s.id);
                              } else {
                                _selectedSourceIds.remove(s.id);
                              }
                            });
                            _doSearch(app);
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

  Widget _buildDoubanStrip(BuildContext context, String label, List<DoubanItem> items) {
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
                          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          label == '电影' ? Icons.movie_creation_outlined : Icons.tv_outlined,
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
                      Text('热门推荐', style: Theme.of(context).textTheme.bodySmall),
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
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  label,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.primary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const Spacer(),
                              if (item.rate > 0)
                                Row(
                                  children: [
                                    const Icon(Icons.star_rounded,
                                        size: 14, color: Colors.amber),
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
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
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
        padding: const EdgeInsets.only(bottom: 28),
        children: [
          _buildDoubanHotSection(context, app),
          if (app.history.isNotEmpty) ...[
            const _SectionHeader(title: '继续观看', subtitle: '回到上次离开的地方'),
            SizedBox(
              height: 144,
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
                          onTap: () => _openDetail(context, item),
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
                                        borderRadius: BorderRadius.circular(999),
                                      ),
                                      child: Text(
                                        '继续观看',
                                        style: TextStyle(
                                          color: Theme.of(context).colorScheme.primary,
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
                                  '上次进度 ${entry.lastPositionSeconds}s',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '观看于 ${_formatDateTime(entry.watchedAt)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall,
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
                onPageChanged: (index) => setState(() => _featuredIndex = index),
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
                              ? Container(color: Theme.of(context).colorScheme.surfaceContainer)
                              : Image.network(
                                  item.poster,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    color: Theme.of(context).colorScheme.surfaceContainer,
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
                                    crossAxisAlignment: CrossAxisAlignment.start,
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
                                  onPressed: () => _openDetail(context, item),
                                  icon: const Icon(Icons.play_arrow),
                                  label: const Text('播放'),
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
                  isFavorite: app.isFavorite(item.id),
                  onFavoriteToggle: () => app.toggleFavorite(item),
                  onPlay: () => _openDetail(context, item),
                  onDetail: () => _openDetail(context, item),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildHistoryTab(BuildContext context) {
    final app = AppScope.of(context);
    if (app.history.isEmpty) {
      return _buildLibraryEmptyState(
        context,
        icon: Icons.history_rounded,
        title: '还没有观看记录',
        subtitle: '开始播放任意内容后，这里会显示最近观看进度和回看入口。',
      );
    }

    final latest = app.history.first;
    final sources = app.history.map((entry) => entry.video.sourceId).toSet().length;
    final totalProgressSeconds = app.history.fold<int>(
      0,
      (sum, entry) => sum + entry.lastPositionSeconds,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
      children: [
        _LibraryHeroCard(
          title: '观看历史',
          subtitle: '像 iOS 媒体资料库一样快速回到最近看过的内容。',
          leadingIcon: Icons.history_rounded,
          stats: [
            _LibraryStat(label: '记录', value: '${app.history.length}'),
            _LibraryStat(label: '来源', value: '$sources'),
            _LibraryStat(label: '累计进度', value: '${totalProgressSeconds ~/ 60} 分钟'),
          ],
        ),
        const _SectionHeader(title: '最近观看', subtitle: '保留最近播放时间和进度信息'),
        SizedBox(
          height: 176,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: app.history.take(8).length,
            itemBuilder: (context, index) {
              final entry = app.history[index];
              return Padding(
                padding: EdgeInsets.only(right: index == 7 ? 0 : 12),
                child: SizedBox(
                  width: 280,
                  child: _HistorySpotlightCard(
                    entry: entry,
                    isFavorite: app.isFavorite(entry.video.id),
                    onFavoriteToggle: () => app.toggleFavorite(entry.video),
                    onTap: () => _openDetail(context, entry.video),
                  ),
                ),
              );
            },
          ),
        ),
        const _SectionHeader(title: '全部记录', subtitle: '按时间倒序展示你的观看历史'),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          itemCount: app.history.length,
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 240,
            mainAxisExtent: 320,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemBuilder: (context, index) {
            final entry = app.history[index];
            final item = entry.video;
            return _VideoGridCard(
              item: item,
              badgeText: _formatDateTime(entry.watchedAt),
              meta:
                  '已观看 ${entry.lastPositionSeconds ~/ 60 > 0 ? '${entry.lastPositionSeconds ~/ 60} 分钟' : '${entry.lastPositionSeconds}s'}',
              isFavorite: app.isFavorite(item.id),
              onFavoriteToggle: () => app.toggleFavorite(item),
              onPlay: () => _openDetail(context, item),
              onDetail: () => _openDetail(context, item),
            );
          },
        ),
        const SizedBox(height: 4),
        _LibraryFooterNote(
          text: '最近一次观看: ${latest.video.title} · ${_formatDateTime(latest.watchedAt)}',
        ),
      ],
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
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
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
              isFavorite: true,
              onFavoriteToggle: () => app.toggleFavorite(item),
              onPlay: () => _openDetail(context, item),
              onDetail: () => _openDetail(context, item),
            );
          },
        ),
        const SizedBox(height: 4),
        const _LibraryFooterNote(
          text: '收藏会同步保存在本地，方便你随时继续浏览或播放。',
        ),
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
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
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
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DetailScreen(item: item),
      ),
    );
  }

  void _syncSelectedSources(AppController app) {
    final enabled = app.sources.where((s) => s.enabled).map((e) => e.id).toSet();
    if (!_sourceSelectionInitialized) {
      _selectedSourceIds = enabled;
      _sourceSelectionInitialized = true;
      return;
    }
    _selectedSourceIds = _selectedSourceIds.intersection(enabled);
  }

  void _onQueryChanged(AppController app) {
    setState(() {});
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 320), () {
      if (!mounted) return;
      _doSearch(app);
    });
  }

  void _doSearch(AppController app) {
    final query = _controller.text.trim();
    if (query.isEmpty) {
      app.loadHomeVideos(sourceIds: _selectedSourceIds);
      return;
    }
    app.search(query, sourceIds: _selectedSourceIds);
  }

  String _formatDateTime(DateTime dt) {
    final local = dt.toLocal();
    final mm = local.month.toString().padLeft(2, '0');
    final dd = local.day.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '$mm-$dd $hh:$min';
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
  const _SectionHeader({
    required this.title,
    required this.subtitle,
  });

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
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 2),
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
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
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
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
                      Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: stats.map((stat) => _LibraryStatChip(stat: stat)).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _LibraryStat {
  const _LibraryStat({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;
}

class _LibraryStatChip extends StatelessWidget {
  const _LibraryStatChip({
    required this.stat,
  });

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

class _HistorySpotlightCard extends StatelessWidget {
  const _HistorySpotlightCard({
    required this.entry,
    required this.isFavorite,
    required this.onFavoriteToggle,
    required this.onTap,
  });

  final PlaybackHistoryItem entry;
  final bool isFavorite;
  final VoidCallback onFavoriteToggle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final item = entry.video;
    final progress = entry.lastPositionSeconds;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            item.poster.isEmpty
                ? Container(color: Theme.of(context).colorScheme.surfaceContainer)
                : Image.network(
                    item.poster,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: Theme.of(context).colorScheme.surfaceContainer,
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
              right: 10,
              top: 10,
              child: IconButton.filledTonal(
                onPressed: onFavoriteToggle,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black45,
                  foregroundColor: Colors.white,
                ),
                icon: Icon(isFavorite ? Icons.favorite : Icons.favorite_border),
              ),
            ),
            Positioned(
              left: 14,
              right: 14,
              bottom: 14,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      progress > 0 ? '已看到 ${progress ~/ 60 > 0 ? '${progress ~/ 60} 分钟' : '${progress}s'}' : '刚开始观看',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.description.isEmpty ? '继续播放或查看详情' : item.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LibraryFooterNote extends StatelessWidget {
  const _LibraryFooterNote({
    required this.text,
  });

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall,
      ),
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
    this.meta,
    this.badgeText,
  });

  final VideoItem item;
  final bool isFavorite;
  final VoidCallback onFavoriteToggle;
  final VoidCallback onPlay;
  final VoidCallback onDetail;
  final String? meta;
  final String? badgeText;

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
                    ? Container(color: Theme.of(context).colorScheme.surfaceContainer)
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
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                    icon: Icon(isFavorite ? Icons.favorite : Icons.favorite_border),
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
            child: Text(
              meta ?? (item.description.isEmpty ? '暂无简介' : item.description),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
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
                    label: const Text('播放'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onDetail,
                    icon: const Icon(Icons.list, size: 16),
                    label: const Text('详情'),
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
