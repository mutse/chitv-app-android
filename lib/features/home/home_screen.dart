import 'package:flutter/material.dart';

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

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);

    if (app.initializing) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('ChiTV Android')),
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
          NavigationDestination(icon: Icon(Icons.search), label: '搜索'),
          NavigationDestination(icon: Icon(Icons.history), label: '历史'),
          NavigationDestination(icon: Icon(Icons.favorite), label: '收藏'),
          NavigationDestination(icon: Icon(Icons.settings), label: '设置'),
        ],
      ),
    );
  }

  Widget _buildSearchTab(BuildContext context) {
    final app = AppScope.of(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: const InputDecoration(
                    hintText: '搜索你喜欢的视频',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => app.search(_controller.text),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: app.searching ? null : () => app.search(_controller.text),
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
        if (app.error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(app.error!, style: const TextStyle(color: Colors.red)),
          ),
        Expanded(
          child: ListView.builder(
            itemCount: app.searchResults.length,
            itemBuilder: (context, index) {
              final item = app.searchResults[index];
              return VideoTile(
                item: item,
                onTap: () => _openDetail(context, item),
                trailing: IconButton(
                  icon: Icon(
                    app.isFavorite(item.id) ? Icons.favorite : Icons.favorite_border,
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
}
