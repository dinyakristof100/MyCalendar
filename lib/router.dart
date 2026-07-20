import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/auth/auth_controller.dart';
import 'features/auth/login_screen.dart';
import 'features/home/home_screen.dart';

/// go_router auth-guarddal: kijelentkezve mindig a /login-ra terel,
/// bejelentkezve a /login-ról a főképernyőre.
final routerProvider = Provider<GoRouter>((ref) {
  // A redirect újrafuttatásához figyeljük az auth állapotot egy Listenable-ön át.
  final refresh = ValueNotifier<AuthUser?>(ref.read(authControllerProvider));
  ref.listen(authControllerProvider, (_, next) => refresh.value = next);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    refreshListenable: refresh,
    initialLocation: '/',
    redirect: (context, state) {
      final signedIn = ref.read(authControllerProvider) != null;
      final loggingIn = state.matchedLocation == '/login';
      if (!signedIn) return loggingIn ? null : '/login';
      if (loggingIn) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (_, _) => const HomeScreen()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
    ],
  );
});
