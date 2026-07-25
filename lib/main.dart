import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'app.dart';
import 'core/cloud_sync.dart';
import 'core/notifications.dart';
import 'core/prefs.dart';
import 'features/calendar/reminders.dart';
import 'features/workouts/workout_nudges.dart';
import 'features/workouts/workout_progress.dart';
import 'firebase_options.dart';
import 'router.dart';

/// A google-services.json-beli "client_type: 3" (web) kliens. Androidon ez kell
/// ahhoz, hogy a bejelentkezés idToken-t adjon vissza, amit a Firebase elfogad.
const _serverClientId =
    '626525324491-ck83hc859qabb5boju5st0iulu1rd4f8.apps.googleusercontent.com';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await GoogleSignIn.instance.initialize(serverClientId: _serverClientId);
    await initPrefs();

    // Saját konténer, hogy az értesítés-koppintás is elérje a routert — az a
    // widget-fán kívülről érkezik.
    final container = ProviderContainer();
    await initNotifications(
      onTap: (route) => container.read(routerProvider).go(route),
      onWorkoutDone: () =>
          container.read(workoutProgressProvider.notifier).markTodayDone(),
      onSnooze: snoozeReminder,
    );
    // Egyszeri beolvasás: innentől a terv és a pipák változását követve
    // újraütemezi az esti kérdéseket.
    container.read(workoutNudgeSyncProvider);
    // Ugyanígy egyszer: bejelentkezéskor visszatölti a felhőből a mentett
    // adatokat (kategóriák, edzéstervek, beállítások), és frissen tartja a TTL-t.
    container.read(cloudSyncProvider);

    runApp(
      UncontrolledProviderScope(
        container: container,
        child: const MyCalendarApp(),
      ),
    );
  } catch (error, stack) {
    // Ha az indulás elhasal (pl. a build kihagyott egy natív plugint), a hiba
    // legyen a képernyőn. Enélkül az app némán az indítóképernyőn marad, és
    // csak logcatből derül ki, mi történt.
    runApp(_StartupError('$error\n\n$stack'));
  }
}

class _StartupError extends StatelessWidget {
  const _StartupError(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: SelectableText(
            'Az app indítása nem sikerült:\n\n$message',
            style: const TextStyle(fontSize: 13),
          ),
        ),
      ),
    ),
  );
}
