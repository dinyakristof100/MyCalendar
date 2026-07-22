import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/auth_controller.dart';

/// A hamburgermenü pontjai. Az útvonalak a routerben ugyanezek.
const _menu = [
  (path: '/', icon: Icons.event_outlined, label: 'Események'),
  (path: '/calendar', icon: Icons.calendar_month_outlined, label: 'Naptár'),
  (path: '/workouts', icon: Icons.fitness_center_outlined, label: 'Edzésnapló'),
  (path: '/settings', icon: Icons.settings_outlined, label: 'Beállítások'),
];

/// Minden bejelentkezés utáni oldal közös váza: fejléc az oldal nevével, jobbról
/// a hamburgermenü. A menügombot a Scaffold teszi ki magától az `endDrawer`
/// mellé — ezért nincs saját ikonunk hozzá.
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
    endDrawer: const _Menu(),
    floatingActionButton: floatingActionButton,
    body: body,
  );
}

class _Menu extends ConsumerWidget {
  const _Menu();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final name = ref.watch(currentUserProvider).value?.name;
    final here = GoRouterState.of(context).matchedLocation;

    return Drawer(
      // ponytail: fix lista, nem ListView — néhány elem, nincs mit görgetni.
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('MyCalendar', style: theme.textTheme.titleLarge),
                  if (name != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      name,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Divider(),
            for (final item in _menu)
              ListTile(
                leading: Icon(item.icon),
                title: Text(item.label),
                selected: item.path == here,
                // A pop csukja a fiókot, a push nyitja az oldalt. Az aktuális
                // oldalra kattintva csak becsukódik.
                //
                // push és nem go: a go lecseréli az útvonal-vermet, onnan a
                // rendszer vissza gombja már az appból lépne ki. Így viszont az
                // előző oldalra visz.
                //
                // ponytail: a verem oda-vissza lépkedéssel nőhet. Néhány oldalnál
                // ez pár elem — ha zavaró lesz, jöhet a „főoldalig ürítés".
                onTap: () {
                  Navigator.pop(context);
                  if (item.path != here) context.push(item.path);
                },
              ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Kijelentkezés'),
              // Nem csukjuk be kézzel: a router a /login-ra visz, azzal a fiók
              // is eltűnik.
              onTap: signOut,
            ),
          ],
        ),
      ),
    );
  }
}
