import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/app_scaffold.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/login_screen.dart';
import 'features/events/events_screen.dart';
import 'features/settings/settings_screen.dart';

/// go_router auth-guarddal: kijelentkezve mindig a /login-ra terel,
/// bejelentkezve a /login-ról a főképernyőre.
final routerProvider = Provider<GoRouter>((ref) {
  // A redirect újrafuttatásához figyeljük az auth állapotot egy Listenable-ön át.
  final refresh = ValueNotifier<AsyncValue<AuthUser?>>(
    ref.read(currentUserProvider),
  );
  ref.listen(currentUserProvider, (_, next) => refresh.value = next);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    refreshListenable: refresh,
    initialLocation: '/',
    redirect: (context, state) {
      final auth = ref.read(currentUserProvider);
      // Amíg a mentett munkamenet töltődik, ne ugráltassuk a felhasználót.
      if (auth.isLoading) return null;
      final signedIn = auth.value != null;
      final loggingIn = state.matchedLocation == '/login';
      if (!signedIn) return loggingIn ? null : '/login';
      if (loggingIn) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (_, _) => const EventsScreen()),
      GoRoute(path: '/calendar', builder: (_, _) => const _Soon('Naptár')),
      GoRoute(path: '/workouts', builder: (_, _) => const _Soon('Edzésnapló')),
      GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
    ],
  );
});

/// Még meg nem épült oldalak: a menüpont már működik, a tartalom jön.
///
/// ponytail: egy közös üres oldal három külön képernyőfájl helyett — amelyik
/// megépül, az kap saját fájlt és lecseréli itt ezt a sort.
class _Soon extends StatelessWidget {
  const _Soon(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppScaffold(
      title: title,
      body: Center(
        child: Text(
          'Hamarosan',
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
