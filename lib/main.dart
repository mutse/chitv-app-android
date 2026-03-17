import 'dart:async';

import 'package:flutter/widgets.dart';

import 'app/app.dart';
import 'app/app_controller.dart';
import 'app/video_repository.dart';
import 'core/storage/local_store.dart';
import 'core/storage/vod_api_client.dart';
import 'core/utils/content_filter.dart';
import 'core/utils/episode_parser.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final controller = AppController(
    localStore: LocalStore(),
    repository: VideoRepository(
      api: VodApiClient(),
      filter: ContentFilter(),
      episodeParser: EpisodeParser(),
    ),
  );

  runApp(ChiTvApp(controller: controller));
  unawaited(controller.init());
}
