import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/help/guide.dart';
import '../features/workouts/motivation.dart';

/// Minden bejelentkezés utáni oldal közös váza: fejléc az oldal nevével. Az
/// oldalak közti váltást az [AppShell] alsó navigációs sávja adja.
class AppScaffold extends StatelessWidget {
  const AppScaffold({
    required this.title,
    required this.body,
    this.floatingActionButton,
    this.actions,
    super.key,
  });

  final String title;
  final Widget body;
  final Widget? floatingActionButton;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title), actions: actions),
    floatingActionButton: floatingActionButton,
    body: body,
  );
}

/// Az alsó navigációs sáv és a fülek állapotát megőrző héj. A fülek sorrendje
/// a router ágainak sorrendje.
///
/// Itt indul az első telepítés utáni bemutató is: ez az első képernyő, ami
/// bejelentkezés után felépül, és a héj a fülváltásokat túléli — így pontosan
/// egyszer fut le.
class AppShell extends StatefulWidget {
  const AppShell({required this.shell, super.key});

  final StatefulNavigationShell shell;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  /// Az edzésnapló füle a router ágai között — a rá lépés forgat egyet a
  /// motivációs szövegeken.
  static const _workoutsTab = 2;

  /// Melyik fülön álltunk az előző felépüléskor: ebből látszik a fülváltás.
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    if (guideSeen) return;
    // Az első képkocka után, hogy legyen mire ráúsztatni a lapot.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showGuide(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    final shell = widget.shell;
    // Fülváltás: a héj minden váltásnál újraépül, a fülek maguk viszont
    // életben maradnak — a képernyők ezért nem veszik észre, hogy megnyitották
    // őket. Az edzésnaplónak ez a jelzés kell az új motivációs szöveghez.
    // Képkocka után léptetünk: építés közben nem piszkálunk más widgetet.
    if (shell.currentIndex != _tab) {
      _tab = shell.currentIndex;
      if (_tab == _workoutsTab) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => motivationSpin.value++,
        );
      }
    }
    return PopScope(
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
}
