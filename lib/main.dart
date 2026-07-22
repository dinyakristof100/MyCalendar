import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'app.dart';
import 'features/calendar/reminders.dart';
import 'features/settings/settings_screen.dart';
import 'firebase_options.dart';

/// A google-services.json-beli "client_type: 3" (web) kliens. Androidon ez kell
/// ahhoz, hogy a bejelentkezés idToken-t adjon vissza, amit a Firebase elfogad.
const _serverClientId =
    '626525324491-ck83hc859qabb5boju5st0iulu1rd4f8.apps.googleusercontent.com';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await GoogleSignIn.instance.initialize(serverClientId: _serverClientId);
  await initReminders();
  await initSettings();
  runApp(const ProviderScope(child: MyCalendarApp()));
}
