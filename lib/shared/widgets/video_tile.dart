import 'package:flutter/material.dart';

import '../../core/models/video_item.dart';

class VideoTile extends StatelessWidget {
  const VideoTile({
    super.key,
    required this.item,
    required this.onTap,
    this.trailing,
    this.subtitle,
  });

  final VideoItem item;
  final VoidCallback onTap;
  final Widget? trailing;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: item.poster.isEmpty
          ? const Icon(Icons.movie_creation_outlined)
          : ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.network(
                item.poster,
                width: 52,
                height: 52,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    const Icon(Icons.broken_image_outlined),
              ),
            ),
      title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        subtitle ?? item.description,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: trailing,
      onTap: onTap,
    );
  }
}
