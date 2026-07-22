import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_calendar/features/calendar/calendar_service.dart';

/// Ahogy a natív oldalról érkezik (lásd MainActivity.queryEvents).
Map<String, Object?> _raw({
  required int begin,
  bool allDay = false,
  String? title = 'Teszt',
  int? end,
  String? description,
  String? location,
}) => {
  'id': '42',
  'title': title,
  'begin': begin,
  'allDay': allDay,
  'end': end,
  'description': description,
  'location': location,
};

void main() {
  test('új esemény: a natív oldal a megbeszélt mezőket kapja', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    MethodCall? sent;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('mycalendar/device_calendar'),
          (call) async {
            sent = call;
            return '7';
          },
        );

    final start = DateTime(2026, 7, 23, 14, 30);
    await createEvent(
      title: 'Fogorvos',
      start: start,
      end: start.add(const Duration(hours: 1)),
    );

    // A MainActivity ezredmásodperceket vár ezeken a kulcsokon.
    expect(sent!.method, 'createEvent');
    expect(sent!.arguments, {
      'title': 'Fogorvos',
      'begin': start.millisecondsSinceEpoch,
      'end': DateTime(2026, 7, 23, 15, 30).millisecondsSinceEpoch,
    });
  });

  test('a vége nem előzheti meg a kezdést', () {
    final start = DateTime(2026, 7, 23, 14, 30);

    // Többnapos: érintetlen marad.
    expect(
      clampEnd(start, DateTime(2026, 7, 25, 10)),
      DateTime(2026, 7, 25, 10),
    );
    // Visszafelé állítva egy órássá igazodik.
    expect(
      clampEnd(start, DateTime(2026, 7, 23, 9)),
      DateTime(2026, 7, 23, 15, 30),
    );
  });

  test('időpontos esemény: helyi időre váltva', () {
    final at = DateTime(2026, 7, 23, 14, 30);
    final event = parseEvent(_raw(begin: at.millisecondsSinceEpoch));

    expect(event.allDay, isFalse);
    expect(event.at, at);
  });

  test('egész napos esemény: nem csúszik át másik napra', () {
    // Az Android UTC éjfélt ad egész napos eseményre. Helyi időként
    // értelmezve pozitív időeltolásnál az előző napra csúszna.
    final begin = DateTime.utc(2026, 7, 23).millisecondsSinceEpoch;
    final event = parseEvent(_raw(begin: begin, allDay: true));

    expect(event.allDay, isTrue);
    expect((event.at.year, event.at.month, event.at.day), (2026, 7, 23));
  });

  test('cím nélküli eseménynek van megjeleníthető neve', () {
    final event = parseEvent(_raw(begin: 0, title: null));
    expect(event.title, isNotEmpty);
  });

  test('formázás: egész napos és időpontos', () {
    final allDay = parseEvent(
      _raw(
        begin: DateTime.utc(2026, 7, 23).millisecondsSinceEpoch,
        allDay: true,
      ),
    );
    final timed = parseEvent(
      _raw(begin: DateTime(2026, 7, 23, 9, 5).millisecondsSinceEpoch),
    );

    expect(formatStart(allDay), '07. 23. egész nap');
    expect(formatStart(timed), '07. 23. 09:05');
  });

  test('részletek: vége, helyszín, leírás', () {
    final at = DateTime(2026, 7, 23, 14, 30);
    final event = parseEvent(
      _raw(
        begin: at.millisecondsSinceEpoch,
        end: at.add(const Duration(hours: 1)).millisecondsSinceEpoch,
        description: '  Hozd a laptopot  ',
        location: '',
      ),
    );

    expect(hhmm(event.end!), '15:30');
    // A körítő szóközök nem tartoznak a tartalomhoz, az üres mező meg nincs.
    expect(event.description, 'Hozd a laptopot');
    expect(event.location, isNull);
  });

  test('egész napos eseménynek nincs mutatható vége', () {
    final begin = DateTime.utc(2026, 7, 23).millisecondsSinceEpoch;
    final event = parseEvent(
      _raw(
        begin: begin,
        allDay: true,
        // Az Android a következő nap UTC éjfelét adja — ez nem időpont.
        end: DateTime.utc(2026, 7, 24).millisecondsSinceEpoch,
      ),
    );

    expect(event.end, isNull);
  });
}
