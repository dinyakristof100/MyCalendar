import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';

class MyCalendarApp extends ConsumerWidget {
  const MyCalendarApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const seed = Colors.indigo;
    return MaterialApp.router(
      title: 'MyCalendar',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: seed)),
      darkTheme: ThemeData(
        colorScheme:
            ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark),
      ),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
