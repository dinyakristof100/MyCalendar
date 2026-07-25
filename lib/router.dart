import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/app_scaffold.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/login_screen.dart';
import 'features/calendar/calendar_screen.dart';
import 'features/events/events_screen.dart';
import 'features/help/guide.dart';
import 'features/settings/settings_screen.dart';
import 'features/workouts/plan_form_screen.dart';
import 'features/workouts/workouts_screen.dart';

/// go_router auth-guarddal: kijelentkezve mindig a /login-ra terel,
/// bejelentkezve a /login-ról a főképernyőre.
///
/// A bejelentkezett oldalak egy [StatefulShellRoute]-ban élnek: az alsó
/// navigációs sáv minden fülön ott van, és a fülek megőrzik az állapotukat
/// (a naptár a lapozott hónapot, az edzésnapló a görgetést) váltás közben is.
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
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/', builder: (_, _) => const EventsScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/calendar',
                builder: (_, _) => const CalendarScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/workouts',
                builder: (_, _) => const WorkoutsScreen(),
                // Alútvonal, hogy a felvitel a listára tegye rá magát: a
                // fejlécben így magától megjelenik a vissza nyíl.
                routes: [
                  GoRoute(
                    path: 'new',
                    builder: (_, _) => const PlanFormScreen(),
                  ),
                  GoRoute(
                    path: 'edit/:id',
                    builder: (_, state) =>
                        PlanFormScreen(planId: state.pathParameters['id']),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (_, _) => const SettingsScreen(),
                routes: [
                  GoRoute(path: 'help', builder: (_, _) => const HelpScreen()),
                ],
              ),
            ],
          ),
        ],
      ),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
    ],
  );
});
