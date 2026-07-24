import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_calendar/core/ui.dart';
import 'package:my_calendar/features/calendar/event_categories.dart';

/// WCAG kontrasztarány két szín között (0.05-ös offszettel).
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (max(la, lb) + 0.05) / (min(la, lb) + 0.05);
}

void main() {
  test('readableOn: sötét háttéren fehér, világoson fekete', () {
    expect(readableOn(Colors.black), Colors.white);
    expect(readableOn(Colors.white), Colors.black);
    expect(readableOn(const Color(0xFF2563EB)), Colors.white); // kék
    expect(readableOn(const Color(0xFFF59E0B)), Colors.black); // borostyán
  });

  test('readableOn a jobban kontrasztáló színt adja vissza', () {
    for (final bg in [Colors.black, Colors.white, const Color(0xFF808080)]) {
      final fg = readableOn(bg);
      final other = fg == Colors.white ? Colors.black : Colors.white;
      expect(
        _contrast(fg, bg),
        greaterThanOrEqualTo(_contrast(other, bg)),
      );
    }
  });

  test('minden kategóriaszín felett olvasható a választott szöveg (AA-közeli)', () {
    for (final color in categoryColors) {
      // A kártya szövege nagy/félkövér — a WCAG AA nagy-szöveg küszöbe 3.0.
      expect(
        _contrast(readableOn(color), color),
        greaterThan(4.0),
        reason: 'gyenge kontraszt: $color',
      );
    }
  });
}
