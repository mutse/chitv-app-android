import 'package:flutter/material.dart';

import '../features/home/home_screen.dart';
import 'app_controller.dart';
import 'app_scope.dart';

class ChiTvApp extends StatelessWidget {
  const ChiTvApp({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      controller: controller,
      child: MaterialApp(
        title: 'ChiTV',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
          useMaterial3: true,
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
