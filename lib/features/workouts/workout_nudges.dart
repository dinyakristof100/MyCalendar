import 'dart:math';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../core/notifications.dart';
import 'motivation.dart';
import 'streak.dart';
import 'workout_plans.dart';
import 'workout_progress.dart';

/// Az esti kérdések a tervet és a pipákat követik: elég egyszer beolvasni
/// (a `main` megteszi), utána minden változásnál magától újraütemez.
final workoutNudgeSyncProvider = Provider<void>((ref) {
  final plan = ref.watch(workoutPlansProvider).active;
  syncWorkoutNudges(
    plan: plan,
    // A hét „lezárva", ha minden nap leedzve VAGY szándékosan kihagyva — a
    // skippelt napra nincs mit kérdezni, az áthozottra viszont van.
    weekResolved: plan != null && ref.watch(currentWeekProvider).resolvedAll(plan),
    // A mai élő sorozat: van-e mit „ne szakíts meg". A sorozat változása is
    // újraütemez, így az értesítés szövege követi.
    streak: ref.watch(streakProvider).live(DateTime.now()),
  );
});

/// Az esti kérdés ideje: 19:30 és 20:30 között, minden nap más percben.
///
/// A véletlen azért kell, hogy ne váljon háttérzajjá egy mindig ugyanakkor
/// érkező értesítés.
const _fromMinutes = 19 * 60 + 30;
const _windowMinutes = 60;

/// Hány napra előre ütemezünk. Az app minden indulásnál és minden pipálásnál
/// újraütemez, tehát ez csak arra kell, hogy egy hétig ki se kelljen nyitni.
const _horizonDays = 7;

const _details = NotificationDetails(
  android: AndroidNotificationDetails(
    'workout_nudges',
    'Edzés emlékeztetők',
    channelDescription: 'Esti kérdés, hogy megvolt-e a mai edzés.',
    importance: Importance.high,
    priority: Priority.high,
    // Este szól, amikor gyakran áll a Ne zavarjanak: emlékeztetőként a mód
    // átengedi, így az órára is kimegy.
    category: AndroidNotificationCategory.reminder,
  ),
  iOS: DarwinNotificationDetails(),
);

/// Beütemezi az esti kérdést a következő [_horizonDays] napra.
///
/// Csak akkor kérdez, ha van aktív terv, és a hét még nincs lezárva: a letudott
/// (leedzett vagy kihagyott) hét hátralévő napjait kihagyjuk, a következő hetet
/// viszont már ütemezzük.
Future<void> syncWorkoutNudges({
  required WorkoutPlan? plan,
  required bool weekResolved,
  int streak = 0,
  DateTime? now,
}) async {
  final from = now ?? DateTime.now();

  // Előbb mindig tiszta lap: a terv és a teljesítés is változhatott.
  for (var day = 0; day < _horizonDays; day++) {
    await notifications.cancel(id: workoutIdBase + day);
  }
  if (plan == null) return;

  final weekDone = weekResolved;
  final nextWeek = weekStartOf(from).add(const Duration(days: 7));
  final random = Random();

  for (var day = 0; day < _horizonDays; day++) {
    final date = DateTime(from.year, from.month, from.day + day);
    // A már letudott hétre nincs mit kérdezni, a következőre még lehet.
    if (weekDone && date.isBefore(nextWeek)) continue;

    final at = date.add(
      Duration(minutes: _fromMinutes + random.nextInt(_windowMinutes + 1)),
    );
    // Ma este már elmúlt az idősáv.
    if (!at.isAfter(from)) continue;

    await notifications.zonedSchedule(
      id: workoutIdBase + day,
      title: 'Megvolt a mai edzés?',
      // A napi gondolkodtató egysoros: ugyanazt mondja, amit aznap az
      // edzésnapló kártyája — determinisztikus, ezért előre ütemezhető.
      // ponytail: a sorozatot a MAI héthez számoljuk, a jövő heti napokra is ez
      // kerül; hét fordulóján kissé elavulhat, de minden app-nyitás/pipa
      // újraütemez, így hamar helyreáll.
      body: '${plan.name} — ${nudgeLineFor(date, streak: streak)}',
      // A koppintás ide visz: az edzésnaplóban lehet pipálni.
      payload: '/workouts',
      scheduledDate: tz.TZDateTime.from(at, tz.UTC),
      notificationDetails: _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }
}
