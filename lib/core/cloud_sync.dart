import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/auth_controller.dart';
import '../features/calendar/event_categories.dart';
import '../features/settings/settings_screen.dart';
import '../features/workouts/streak.dart';
import '../features/workouts/workout_plans.dart';
import '../features/workouts/workout_progress.dart';
import 'prefs.dart';

/// Minden felhasználó által létrehozott adat ugyanezen kulcsok alatt él a helyi
/// tárban ÉS a Firestore user-dokumentumában — a kettő egymás tükre. Új
/// szinkronizált beállítás bekerülésekor csak ide kell felvenni a kulcsot.
const syncedKeys = <String>[
  'themeMode', // színkészlet
  'eventCategories', // naptárkategóriák (név + szín)
  'eventCategoryAssignments', // esemény -> kategória
  'workoutPlans', // edzéstervek
  'activeWorkoutPlan', // az aktív terv
  'workoutProgress', // a hét teljesített napjai
  'carryOverWorkouts', // le nem edzett napok átcsúsztatása
  'workoutStreak', // heti sorozat (hány hét zsinórban)
];

/// A `lastActiveAt` minden felhőírásnál a szerveridőre frissül. Automatikus
/// takarítást nem futtatunk — az inaktív fiókok törlését a fejlesztő kézzel
/// intézi a Firebase konzolon; ez a mező ehhez ad támpontot (ki mikor volt
/// utoljára aktív).
///
/// Van-e hova szinkronizálni: fut a Firebase (tesztben nem) és van bejelentkezett
/// felhasználó. Enélkül minden felhőművelet csendes noop — a helyi tár marad.
bool get _cloudReady =>
    Firebase.apps.isNotEmpty && FirebaseAuth.instance.currentUser != null;

DocumentReference<Map<String, dynamic>>? _userDoc() {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return null;
  return FirebaseFirestore.instanceFor(
    app: Firebase.app(),
    databaseId: 'mycalendardb', // NEM a (default) — lásd project-status.
  ).collection('users').doc(uid);
}

/// Beállítás mentése: helyben azonnal (ez a forrás a UI-nak), és — ha van
/// bejelentkezett felhasználó — a felhőbe is, tűzd-és-felejtsd módon. A felhőhiba
/// (offline, jogosultság) sosem csaphat vissza a UI-ra: a helyi írás már megvolt.
Future<void> saveSetting(String key, String value) async {
  await prefs.setString(key, value);
  _pushToCloud({key: value});
}

/// A közös felhőírás: a megadott mezők + a friss `lastActiveAt` bélyeg,
/// merge-dzsel (a többi mezőt nem bántja).
void _pushToCloud(Map<String, Object?> fields) {
  final doc = _cloudReady ? _userDoc() : null;
  if (doc == null) return;
  unawaited(
    doc.set({
      ...fields,
      'lastActiveAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true)).catchError((_) {}),
  );
}

/// Csak a `lastActiveAt` bélyeget frissíti — hogy a kézi takarításnál pontos
/// legyen az „utoljára aktív" időpont. Minden bejelentkezéskor (app indulás) hívjuk.
void touchActivity() => _pushToCloud(const {});

/// Bejelentkezéskor összefésüli a felhőt a helyi tárral:
/// - ha a felhőben már van mentett adat, az a forrás → letöltjük helyibe (ez a
///   „letöröltem, újratelepítettem, bejelentkezem" visszaállás);
/// - ha még nincs (első bejelentkezés ezzel a fiókkal), a meglévő helyi adatot
///   töltjük fel, hogy a dokumentum létrejöjjön.
///
/// ponytail: a felhő a belépéskori forrás, nincs mezőnkénti ütközésfeloldás — egy
/// felhasználó, jellemzően egy eszköz. Ha valaha kell, ide jön a merge.
Future<void> pullFromCloud() async {
  final doc = _cloudReady ? _userDoc() : null;
  if (doc == null) return;
  final data = (await doc.get()).data();
  final cloudHasData = data != null && syncedKeys.any((k) => data[k] is String);
  if (cloudHasData) {
    for (final key in syncedKeys) {
      final value = data[key];
      if (value is String) await prefs.setString(key, value);
    }
    touchActivity();
  } else {
    _pushToCloud({
      for (final key in syncedKeys) key: ?prefs.getString(key),
    });
  }
}

/// Bejelentkezéskor visszatölti a felhőt, majd a friss értékekkel újraépíti az
/// érintett providereket. A `main` egyszer beolvassa (mint a nudge-szinkront),
/// utána a be-/kijelentkezés váltásait követi.
final cloudSyncProvider = Provider<void>((ref) {
  ref.listen<AsyncValue<AuthUser?>>(currentUserProvider, (prev, next) {
    final signedIn = next.value != null;
    final wasSignedIn = prev?.value != null;
    if (!signedIn || wasSignedIn) return; // csak a bejelentkezés pillanatában
    unawaited(
      pullFromCloud().then((_) {
        ref.invalidate(appStyleProvider);
        ref.invalidate(categoriesProvider);
        ref.invalidate(workoutPlansProvider);
        ref.invalidate(workoutProgressProvider);
        ref.invalidate(carryOverProvider);
        ref.invalidate(streakProvider);
      }),
    );
  }, fireImmediately: true);
});
