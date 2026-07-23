import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Minden bejelentkezés utáni oldal közös váza: fejléc az oldal nevével. Az
/// oldalak közti váltást az [AppShell] alsó navigációs sávja adja.
class AppScaffold extends StatelessWidget {
  const AppScaffold({
    required this.title,
    required this.body,
    this.floatingActionButton,
    super.key,
  });

  final String title;
  final Widget body;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    floatingActionButton: floatingActionButton,
    body: body,
  );
}

/// Az alsó navigációs sáv és a fülek állapotát megőrző héj. A fülek sorrendje
/// a router ágainak sorrendje.
class AppShell extends StatelessWidget {
  const AppShell({required this.shell, super.key});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) => PopScope(
    // A rendszer vissza gombja nem lép ki azonnal az appból: a többi fülről
    // előbb a főképernyőre visz, és csak onnan zárja az appot. A fülön belüli
    // alsó oldalakat (pl. edzésterv-felvitel) a router előbb magától zárja.
    canPop: shell.currentIndex == 0,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) shell.goBranch(0);
    },
    child: Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (index) => shell.goBranch(
          index,
          // Az aktív fülre koppintva a fül a saját kezdőoldalára ugrik vissza.
          initialLocation: index == shell.currentIndex,
        ),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.event_outlined),
            selectedIcon: Icon(Icons.event),
            label: 'Események',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Naptár',
          ),
          NavigationDestination(
            icon: Icon(Icons.fitness_center_outlined),
            selectedIcon: Icon(Icons.fitness_center),
            label: 'Edzésnapló',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Beállítások',
          ),
        ],
      ),
    ),
  );
}
