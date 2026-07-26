import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/settings/settings_screen.dart';
import 'features/settings/wallpaper.dart';
import 'router.dart';

/// A felület a kiválasztott stílus akcentszínéből épül (lásd [appStyleProvider]).
/// A Material 3 a seedből képzi a felületszíneket is, így a „szürkék” enyhén az
/// akcent felé húznak ahelyett, hogy semleges alapértelmezések lennének.
ThemeData _theme(Brightness brightness, Color seed, {required bool wallpaper}) {
  final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
  return ThemeData(
    colorScheme: scheme,
    // Háttérkép esetén a lapok átlátszóak, hogy a mögéjük festett kép látsszon.
    // A fejléc és az alsó sáv marad átlátszatlan — ott a szöveg olvashatósága
    // fontosabb.
    scaffoldBackgroundColor: wallpaper ? Colors.transparent : null,
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
    final style = ref.watch(appStyleProvider);
    final wallpaper = ref.watch(wallpaperProvider);
    return MaterialApp.router(
      title: 'MyCalendar',
      debugShowCheckedModeBanner: false,
      // Az app magyar: a natív dátum-/időválasztó így hétfővel kezdi a hetet és
      // magyar feliratú, egyezve az app saját naptárrácsával.
      locale: const Locale('hu'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('hu')],
      theme: _theme(
        Brightness.light,
        style.seed,
        wallpaper: wallpaper != null,
      ),
      darkTheme: _theme(
        Brightness.dark,
        style.seed,
        wallpaper: wallpaper != null,
      ),
      themeMode: style.mode,
      scrollBehavior: const _NoOverscroll(),
      builder: wallpaper == null
          ? null
          : (context, child) => Wallpaper(path: wallpaper, child: child!),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
