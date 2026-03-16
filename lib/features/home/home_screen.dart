import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app/app_scope.dart';
import '../../core/models/video_item.dart';
import '../../shared/widgets/video_tile.dart';
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
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset('assets/logo.png', width: 24, height: 24),
            const SizedBox(width: 8),
            const Text('ChiTV Android'),
          ],
        ),
        actions: [
          if (_tab == 0)
            IconButton(
              onPressed: () => app.loadHomeVideos(sourceIds: _selectedSourceIds),
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
      body: switch (_tab) {
        0 => _buildSearchTab(context),
        1 => _buildHistoryTab(context),
        2 => _buildFavoritesTab(context),
        _ => const SettingsScreen(),
      },
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (v) => setState(() => _tab = v),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.search), label: '首页/搜索'),
          NavigationDestination(icon: Icon(Icons.history), label: '历史'),
          NavigationDestination(icon: Icon(Icons.favorite), label: '收藏'),
          NavigationDestination(icon: Icon(Icons.settings), label: '设置'),
        ],
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
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: InputDecoration(
                    hintText: '搜索你喜欢的视频',
                    border: const OutlineInputBorder(),
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
              const SizedBox(width: 8),
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
        ),
        _buildSourceFilterBar(app),
        if (!showSearchResults && app.recentSearches.isNotEmpty)
          SizedBox(
            height: 48,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              scrollDirection: Axis.horizontal,
              children: [
                ...app.recentSearches.map((text) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ActionChip(
                      label: Text(text),
                      onPressed: () {
                        _controller.text = text;
                        setState(() {});
                        _doSearch(app);
                      },
                    ),
                  );
                }),
                ActionChip(
                  avatar: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('清空历史'),
                  onPressed: app.clearSearchHistory,
                ),
              ],
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
      return const Center(child: Text('未找到匹配结果'));
    }

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: list.length,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 240,
        mainAxisExtent: 300,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemBuilder: (context, index) {
        final item = list[index];
        return _VideoGridCard(
          item: item,
          isFavorite: app.isFavorite(item.id),
          onFavoriteToggle: () => app.toggleFavorite(item),
          onPlay: () => _openDetail(context, item),
          onDetail: () => _openDetail(context, item),
        );
      },
    );
  }

  Widget _buildHomeFeed(BuildContext context, AppController app) {
    if (app.loadingHome) {
      return const Center(child: CircularProgressIndicator());
    }
    if (app.homeVideos.isEmpty) {
      return const Center(child: Text('暂无首页内容，请检查视频源'));
    }

    final featured = app.homeVideos.take(5).toList();
    final others = app.homeVideos.skip(featured.length).toList();

    return RefreshIndicator(
      onRefresh: () => app.loadHomeVideos(sourceIds: _selectedSourceIds),
      child: ListView(
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          if (app.history.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 8, 12, 6),
              child: Text(
                '继续观看',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            SizedBox(
              height: 122,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: app.history.take(8).map((entry) {
                  final item = entry.video;
                  return Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: SizedBox(
                      width: 200,
                      child: Card(
                        child: InkWell(
                          onTap: () => _openDetail(context, item),
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 6),
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
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Text(
                '精选推荐',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            SizedBox(
              height: 220,
              child: PageView.builder(
                itemCount: featured.length,
                onPageChanged: (index) => setState(() => _featuredIndex = index),
                itemBuilder: (context, index) {
                  final item = featured[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
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
                          const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Colors.transparent, Colors.black54],
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
                                  child: Text(
                                    item.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: Colors.black,
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
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 14, 12, 8),
            child: Text(
              '更多视频',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
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

  Widget _buildSourceFilterBar(AppController app) {
    final enabled = app.sources.where((s) => s.enabled).toList();
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
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
    );
  }

  Widget _buildHistoryTab(BuildContext context) {
    final app = AppScope.of(context);
    return ListView.builder(
      itemCount: app.history.length,
      itemBuilder: (context, index) {
        final item = app.history[index];
        return VideoTile(
          item: item.video,
          subtitle: '上次观看: ${item.watchedAt.toLocal()}',
          onTap: () => _openDetail(context, item.video),
        );
      },
    );
  }

  Widget _buildFavoritesTab(BuildContext context) {
    final app = AppScope.of(context);
    return ListView.builder(
      itemCount: app.favorites.length,
      itemBuilder: (context, index) {
        final item = app.favorites[index];
        return VideoTile(
          item: item,
          onTap: () => _openDetail(context, item),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => app.toggleFavorite(item),
          ),
        );
      },
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
}

class _VideoGridCard extends StatelessWidget {
  const _VideoGridCard({
    required this.item,
    required this.isFavorite,
    required this.onFavoriteToggle,
    required this.onPlay,
    required this.onDetail,
  });

  final VideoItem item;
  final bool isFavorite;
  final VoidCallback onFavoriteToggle;
  final VoidCallback onPlay;
  final VoidCallback onDetail;

  @override
  Widget build(BuildContext context) {
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
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
            child: Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              item.description.isEmpty ? '暂无简介' : item.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
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
