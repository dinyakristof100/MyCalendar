import 'package:flutter_test/flutter_test.dart';
import 'package:my_calendar/features/workouts/streak.dart';

void main() {
  final w1 = DateTime(2026, 7, 6); // hétfő
  final w2 = DateTime(2026, 7, 13);
  final w3 = DateTime(2026, 7, 20);
  final w4 = DateTime(2026, 7, 27);

  test('folytonos hetek növelik a sorozatot, ugyanaz a hét nem duplázódik', () {
    var s = const Streak().advance(w1);
    expect(s.weeks, 1);
    s = s.advance(w2);
    expect(s.weeks, 2);
    s = s.advance(w2); // ugyanaz a hét újra
    expect(s.weeks, 2);
    s = s.advance(w3);
    expect(s.weeks, 3);
  });

  test('kihagyott hét után új sorozat indul 1-től', () {
    final s = const Streak().advance(w1).advance(w3); // w2 kimaradt
    expect(s.weeks, 1);
    expect(s.lastWeek, w3);
  });

  test('live: a mai és az előző héten él, régebbin megszakad', () {
    final s = Streak(weeks: 3, lastWeek: w2);
    // Ugyanaz a hét, később:
    expect(s.live(w2.add(const Duration(days: 2))), 3);
    // Előző hét kész, ez a hét folyamatban:
    expect(s.live(w3.add(const Duration(days: 1))), 3);
    // Egy teljes hét kimaradt (w4) → megszakadt:
    expect(s.live(w4.add(const Duration(days: 1))), 0);
  });

  test('a visszavont pipa leszedi az utolsó hetet a sorozatról', () {
    // 3 hét zsinórban, az utolsó a w3 — a w3 egyik napját visszaállítják.
    final s = Streak(weeks: 3, lastWeek: w3).revoke(w3);
    expect(s.weeks, 2);
    expect(s.lastWeek, w2);
    // Az egyetlen hét visszavonásával nem marad sorozat.
    expect(Streak(weeks: 1, lastWeek: w3).revoke(w3).weeks, 0);
    expect(Streak(weeks: 1, lastWeek: w3).revoke(w3).lastWeek, isNull);
    // Régebbi hétre nem nyúl.
    expect(Streak(weeks: 3, lastWeek: w3).revoke(w2).weeks, 3);
  });

  test('json oda-vissza megőrzi az állapotot', () {
    final s = Streak(weeks: 4, lastWeek: w3);
    final back = Streak.fromJson(s.toJson());
    expect(back.weeks, 4);
    expect(back.lastWeek, w3);
  });
}
