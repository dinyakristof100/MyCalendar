import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/settings/settings_screen.dart';
import 'router.dart';

/// Az app akcentszíne. Ugyanez az indigó van az ikonban és a webes oldalakon —
/// a Material 3 ebből képzi a felületszíneket is, így a "szürkék" enyhén az
/// akcent felé húznak ahelyett, hogy semleges alapértelmezések lennének.
const _seed = Color(0xFF3F51B5);

ThemeData _theme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
  return ThemeData(
    colorScheme: scheme,
    appBarTheme: const AppBarTheme(centerTitle: false),
    dividerTheme: const DividerThemeData(space: 1, thickness: 1),
  );
}

/// Túlhúzáskor az Androidon alapértelmezett nyújtás az egész tartalmat
/// elmozdítja — frissítéskor a szövegek is lecsúsznának. A visszajelzést a
/// RefreshIndicator adja, a nyújtás csak zavarna.
class _NoOverscroll extends MaterialScrollBehavior {
  const _NoOverscroll();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
}

class MyCalendarApp extends ConsumerWidget {
  const MyCalendarApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'MyCalendar',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: ref.watch(themeModeProvider),
      scrollBehavior: const _NoOverscroll(),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
