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
    final s = Streak(weeks: 4, lastWeek: w3, completedWeeks: {w2, w3});
    final back = Streak.fromJson(s.toJson());
    expect(back.weeks, 4);
    expect(back.lastWeek, w3);
    expect(back.completedWeeks, {w2, w3});
  });

  test('a teljesített hetek halmaza követi az advance/revoke-ot', () {
    final s = const Streak().advance(w1).advance(w2).advance(w3);
    expect(s.completedWeeks, {w1, w2, w3});
    expect(s.revoke(w3).completedWeeks, {w1, w2});
    // Az egyetlen hét visszavonásával a halmaz is kiürül.
    final none = Streak(
      weeks: 1,
      lastWeek: w1,
      completedWeeks: {w1},
    ).revoke(w1);
    expect(none.weeks, 0);
    expect(none.completedWeeks, isEmpty);
    // Régebbi hétre nem nyúl.
    expect(s.revoke(w1).completedWeeks, {w1, w2, w3});
  });

  test('régi, mezőtlen JSON üres halmazzal olvas be, a pipa feltölti', () {
    final old = Streak.fromJson({'weeks': 2, 'lastWeek': w2.toIso8601String()});
    expect(old.completedWeeks, isEmpty);
    expect(old.weeks, 2);
    // Ugyanannak a hétnek az újrapipálása nem duplázza a sorozatot, csak
    // pótolja a hiányzó hetet a halmazban.
    final fixed = old.advance(w2);
    expect(fixed.weeks, 2);
    expect(fixed.completedWeeks, {w2});
  });

  test('lastWeeks: a mai héttől visszafelé, [0] a mai hét', () {
    final s = const Streak(completedWeeks: {}).advance(w1).advance(w3);
    // w3 közepén állva: [0]=w3 kész, [1]=w2 kimaradt, [2]=w1 kész.
    expect(s.lastWeeks(w3.add(const Duration(days: 3)), 4), [
      true,
      false,
      true,
      false,
    ]);
    expect(s.lastWeeks(w3, 0), isEmpty);
    // A halmazon túlnyúló ablak csupa false-szal folytatódik.
    expect(s.lastWeeks(w3, 10).sublist(3), everyElement(isFalse));
  });

  test('íráskor csak a legutóbbi 26 hét marad meg', () {
    var s = const Streak();
    for (var i = 0; i < 40; i++) {
      s = s.advance(DateTime(2026, 1, 5 + 7 * i)); // 2026-01-05 hétfő
    }
    expect(s.completedWeeks.length, 40); // memóriában még mind
    final kept = Streak.fromJson(s.toJson()).completedWeeks;
    expect(kept.length, 26);
    expect(
      kept.contains(DateTime(2026, 1, 5 + 7 * 39)),
      isTrue,
    ); // a legfrissebb
    expect(
      kept.contains(DateTime(2026, 1, 5 + 7 * 14)),
      isTrue,
    ); // a 26. hátulról
    expect(
      kept.contains(DateTime(2026, 1, 5 + 7 * 13)),
      isFalse,
    ); // már levágva
  });
}
