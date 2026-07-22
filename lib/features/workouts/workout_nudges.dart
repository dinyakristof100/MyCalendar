import 'dart:math';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../core/notifications.dart';
import 'workout_plans.dart';
import 'workout_progress.dart';

/// Az esti kérdések a tervet és a pipákat követik: elég egyszer beolvasni
/// (a `main` megteszi), utána minden változásnál magától újraütemez.
final workoutNudgeSyncProvider = Provider<void>((ref) {
  syncWorkoutNudges(
    plan: ref.watch(workoutPlansProvider).active,
    progress: ref.watch(workoutProgressProvider),
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
/// Csak akkor kérdez, ha van aktív terv, és a hét még nincs kipipálva: a
/// letudott hét hátralévő napjait kihagyjuk, a következő hetet viszont már
/// ütemezzük.
Future<void> syncWorkoutNudges({
  required WorkoutPlan? plan,
  required WeekProgress progress,
  DateTime? now,
}) async {
  final from = now ?? DateTime.now();

  // Előbb mindig tiszta lap: a terv és a teljesítés is változhatott.
  for (var day = 0; day < _horizonDays; day++) {
    await notifications.cancel(id: workoutIdBase + day);
  }
  if (plan == null) return;

  final weekDone = progress.weekDoneFor(plan, from);
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
      body: '${plan.name} — pipáld ki, melyik napot csináltad meg.',
      // A koppintás ide visz: az edzésnaplóban lehet pipálni.
      payload: '/workouts',
      scheduledDate: tz.TZDateTime.from(at, tz.UTC),
      notificationDetails: _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }
}
