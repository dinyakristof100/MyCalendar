import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis/calendar/v3.dart';
import 'package:my_calendar/features/calendar/calendar_service.dart';

/// Ahogy a Calendar API válaszából érkezne, hogy a JSON-parse is benne legyen.
Event _event(Map<String, Object?> start) => Event.fromJson({'start': start});

void main() {
  test('időpontos esemény: helyi időre váltva, allDay = false', () {
    final start = eventStart(_event({'dateTime': '2026-07-23T14:30:00Z'}))!;
    expect(start.allDay, isFalse);
    expect(start.at.isUtc, isFalse);
    expect(start.at.toUtc().hour, 14);
  });

  test('egész napos esemény: nem csúszik át másik napra', () {
    final start = eventStart(_event({'date': '2026-07-23'}))!;
    expect(start.allDay, isTrue);
    expect((start.at.month, start.at.day), (7, 23));
  });

  test('kezdés nélküli eseményre null', () {
    expect(eventStart(Event()), isNull);
  });
}
