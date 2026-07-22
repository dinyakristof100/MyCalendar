import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'app.dart';
import 'core/notifications.dart';
import 'core/prefs.dart';
import 'features/workouts/workout_nudges.dart';
import 'firebase_options.dart';
import 'router.dart';

/// A google-services.json-beli "client_type: 3" (web) kliens. Androidon ez kell
/// ahhoz, hogy a bejelentkezés idToken-t adjon vissza, amit a Firebase elfogad.
const _serverClientId =
    '626525324491-ck83hc859qabb5boju5st0iulu1rd4f8.apps.googleusercontent.com';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await GoogleSignIn.instance.initialize(serverClientId: _serverClientId);
  await initPrefs();

  // Saját konténer, hogy az értesítés-koppintás is elérje a routert — az a
  // widget-fán kívülről érkezik.
  final container = ProviderContainer();
  await initNotifications(
    onTap: (route) => container.read(routerProvider).go(route),
  );
  // Egyszeri beolvasás: innentől a terv és a pipák változását követve
  // újraütemezi az esti kérdéseket.
  container.read(workoutNudgeSyncProvider);

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const MyCalendarApp(),
    ),
  );
}
