import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

// ponytail: Firebase.initializeApp kerül ide a 3b lépésben (miután megvan a
//           firebase_options.dart a `flutterfire configure`-ből).
void main() {
  runApp(const ProviderScope(child: MyCalendarApp()));
}
