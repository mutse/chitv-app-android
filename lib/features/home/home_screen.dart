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
  Set<String> _selectedSourceIds = <String>{};

  @override
  void dispose() {
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
        title: const Text('ChiTV Android'),
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
    final list = showSearchResults ? app.searchResults : app.homeVideos;

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
                  onChanged: (_) => setState(() {}),
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
            height: 44,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              scrollDirection: Axis.horizontal,
              children: app.recentSearches.map((text) {
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
              }).toList(),
            ),
          ),
        if (app.error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(app.error!, style: const TextStyle(color: Colors.red)),
          ),
        Expanded(
          child: (showSearchResults && app.searching) || (!showSearchResults && app.loadingHome)
              ? const Center(child: CircularProgressIndicator())
              : list.isEmpty
                  ? Center(
                      child: Text(showSearchResults ? '未找到匹配结果' : '暂无首页内容，请检查视频源'),
                    )
                  : ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (context, index) {
                        final item = list[index];
                        return VideoTile(
                          item: item,
                          onTap: () => _openDetail(context, item),
                          trailing: IconButton(
                            icon: Icon(
                              app.isFavorite(item.id)
                                  ? Icons.favorite
                                  : Icons.favorite_border,
                              color: Colors.pink,
                            ),
                            onPressed: () => app.toggleFavorite(item),
                          ),
                        );
                      },
                    ),
        ),
      ],
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
                setState(() => _selectedSourceIds = enabled.map((e) => e.id).toSet());
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
                    if (_selectedSourceIds.isEmpty) {
                      _selectedSourceIds = enabled.map((e) => e.id).toSet();
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
    if (_selectedSourceIds.isEmpty) {
      _selectedSourceIds = enabled;
      return;
    }
    _selectedSourceIds = _selectedSourceIds.intersection(enabled);
    if (_selectedSourceIds.isEmpty) {
      _selectedSourceIds = enabled;
    }
  }

  void _doSearch(AppController app) {
    final query = _controller.text.trim();
    if (query.isEmpty) {
      app.loadHomeVideos(sourceIds: _selectedSourceIds);
      return;
    }
    app.search(query, sourceIds: _selectedSourceIds);
  }
}
