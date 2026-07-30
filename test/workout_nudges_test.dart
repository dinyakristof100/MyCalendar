import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_calendar/core/notifications.dart';
import 'package:my_calendar/core/prefs.dart';
import 'package:my_calendar/features/workouts/workout_nudges.dart';
import 'package:my_calendar/features/workouts/workout_plans.dart';
import 'package:my_calendar/features/workouts/workout_progress.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;

const _channel = MethodChannel('dexterous.com/flutter/local_notifications');

const _plan = WorkoutPlan(
  id: 'p',
  name: 'Terv',
  weeks: [
    ['mell', 'hát', 'láb'],
  ],
);

/// A tesztek napja: a következő hétfő reggel. A plugin elutasítja a múltbeli
/// időpontot, tehát fix dátum nem jó — hétfő viszont kell, mert épp a hét
/// elején lezárt hét a régi hiba.
final _monday = () {
  final next = weekStartOf(DateTime.now()).add(const Duration(days: 7));
  return DateTime(next.year, next.month, next.day, 10);
}();

void main() {
  final calls = <MethodCall>[];

  /// A beütemezett kérdések helyi ideje, ütemezés sorrendjében.
  List<DateTime> scheduled() => [
    for (final call in calls)
      if (call.method == 'zonedSchedule')
        DateTime.parse(
          (call.arguments as Map)['scheduledDateTimeISO8601'] as String,
        ).toLocal(),
  ];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await initPrefs();
    tzdata.initializeTimeZones();
    // A plugin platform-implementációját a natív oldal kötné be; tesztben
    // kézzel, hogy a metóduscsatorna hívásai megfoghatók legyenek.
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    FlutterLocalNotificationsPlatform.instance =
        AndroidFlutterLocalNotificationsPlugin();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          calls.add(call);
          // A ki nem sült kérdések listája: egy edzés-azonosító és egy
          // naptáré. A már kiírt (elsült) értesítés ebben nincs benne.
          if (call.method == 'pendingNotificationRequests') {
            return [
              {'id': workoutIdBase + 3, 'title': null, 'body': null},
              {'id': 42, 'title': null, 'body': null},
            ];
          }
          return null;
        });
  });

  setUp(calls.clear);

  test('nyitott hét: minden napra jut kérdés, este', () async {
    await syncWorkoutNudges(plan: _plan, weekResolved: false, now: _monday);
    final at = scheduled();
    expect(at, hasLength(14));
    expect(at.first.day, _monday.day); // a mai este is benne van
    for (final when in at) {
      expect(
        when.hour * 60 + when.minute,
        inInclusiveRange(19 * 60 + 30, 20 * 60 + 30),
      );
    }
  });

  test(
    'lezárt hét: a hátralévő napok kimaradnak, a következő hét megvan',
    () async {
      await syncWorkoutNudges(
        plan: _plan,
        weekResolved: true,
        now: _monday, // hétfő: az egész hét már letudva
      );
      // Regresszió: egyhetes ablakkal ilyenkor NULLA kérdés maradt, és mivel az
      // app nem szólt, ki sem nyitották — a kérdés végleg elnémult.
      final at = scheduled();
      expect(at, hasLength(7));
      // A következő hét hétfője — a mai héten már nincs mit kérdezni.
      expect(at.first.day, _monday.add(const Duration(days: 7)).day);
    },
  );

  test('új hét: a lezárt előző hét után tiszta lapról kérdez', () async {
    final cur = weekStartOf(DateTime.now());
    final lastWeek = DateTime(cur.year, cur.month, cur.day - 7);
    await prefs.setString('workoutPlans', jsonEncode([_plan.toJson()]));
    await prefs.setString('activeWorkoutPlan', _plan.id);
    await prefs.setString(
      'workoutProgress',
      // Az előző hét mind a három napja letudva — az a hét le volt zárva.
      jsonEncode(
        WeekProgress(
          planId: _plan.id,
          weekStart: lastWeek,
          done: const {0, 1, 2},
        ).toJson(),
      ),
    );

    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.listen(workoutNudgeSyncProvider, (_, _) {});
    await Future<void>.delayed(const Duration(milliseconds: 50));

    // Este futtatva a mai nap ablaka már elmúlt, akkor 13 — a lényeg, hogy a
    // lezárt előző hét nem viszi magával az újat.
    expect(scheduled().length, greaterThanOrEqualTo(13));
  });

  test('kikapcsolt kapcsoló: csak törlés marad', () async {
    await syncWorkoutNudges(
      plan: _plan,
      weekResolved: false,
      enabled: false,
      now: _monday,
    );
    expect(scheduled(), isEmpty);
    // A már beütemezett kérdést viszont leszedi — és CSAK azt: a naptár
    // emlékeztetője (42) marad, a fiókban álló, már kiírt kérdés szintén,
    // mert az nincs a `pending` listán.
    expect(
      [
        for (final c in calls)
          if (c.method == 'cancel') c.arguments,
      ],
      [containsPair('id', workoutIdBase + 3)],
    );
  });
}
