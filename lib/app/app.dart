import 'package:flutter/material.dart';

import '../features/home/home_screen.dart';
import 'app_controller.dart';
import 'app_scope.dart';
import 'app_theme.dart';

class ChiTvApp extends StatelessWidget {
  const ChiTvApp({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      controller: controller,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          return MaterialApp(
            title: 'ChiTV',
            themeMode: _themeModeFrom(controller.settings.appThemeMode),
            theme: buildChiTvTheme(Brightness.light),
            darkTheme: buildChiTvTheme(Brightness.dark),
            home: const HomeScreen(),
          );
        },
      ),
    );
  }

  ThemeMode _themeModeFrom(String value) {
    return switch (value) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }
}
