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
  String? rrule,
}) => {
  'id': '42',
  'title': title,
  'begin': begin,
  'allDay': allDay,
  'end': end,
  'description': description,
  'location': location,
  'rrule': rrule,
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
      'allDay': false,
    });
  });

  test('egész napos esemény: UTC éjféltől a következő UTC éjfélig', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    MethodCall? sent;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('mycalendar/device_calendar'),
          (call) async {
            sent = call;
            return null;
          },
        );

    // A választott nap délutánja — az időpontnak el kell tűnnie.
    await createEvent(
      title: 'Szabadság',
      start: DateTime(2026, 7, 23, 14, 30),
      end: DateTime(2026, 7, 23, 15, 30),
      allDay: true,
    );

    expect(sent!.arguments, {
      'title': 'Szabadság',
      'begin': DateTime.utc(2026, 7, 23).millisecondsSinceEpoch,
      // Félig nyílt intervallum: a vég a következő nap UTC éjfele.
      'end': DateTime.utc(2026, 7, 24).millisecondsSinceEpoch,
      'allDay': true,
    });
  });

  test('helyi nap → UTC éjfél: az óraátállítás napjain sem csúszik', () {
    // A magyar zóna pozitív eltolású, ezért a `toUtc()` az előző napra vinné.
    // A két óraátállítás napja a kényes eset: ott a helyi nap 23, illetve 25
    // órás, a UTC nap viszont mindig 24 — a dátumnak ettől nem szabad
    // elmozdulnia.
    for (final day in [
      DateTime(2026, 3, 29), // tavaszi előreállítás (02:00 → 03:00)
      DateTime(2026, 10, 25), // őszi visszaállítás (03:00 → 02:00)
      DateTime(2026, 7, 23), // sima nyári nap
      DateTime(2026, 1, 15), // sima téli nap
    ]) {
      final utc = utcMidnight(day);
      expect(
        (utc.year, utc.month, utc.day),
        (day.year, day.month, day.day),
        reason: 'a naptári napnak változatlannak kell maradnia: $day',
      );
      expect(utc.isUtc, isTrue);
      expect((utc.hour, utc.minute, utc.second), (0, 0, 0));

      // Oda-vissza: amit így beírunk, azt a natív oldal ugyanerre a napra adja
      // vissza — erre épül az emlékeztető „előző nap 18:00" ága is.
      final event = parseEvent(
        _raw(begin: utc.millisecondsSinceEpoch, allDay: true),
      );
      expect((event.at.year, event.at.month, event.at.day), (
        day.year,
        day.month,
        day.day,
      ));
    }
  });

  test('egész napos délutáni időpontból is a helyes napot írja', () {
    // 14:30-kor a `toUtc()` +2 órás zónában 12:30 UTC-t adna — ugyanazon a
    // napon —, de a hajnali óráknál már az előző napra csúszna. A mezők
    // átvétele ezért kötelező.
    final start = DateTime(2026, 7, 23, 1, 15);
    expect(utcMidnight(start), DateTime.utc(2026, 7, 23));
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

  test('ismétlődés szabálya: a heti a kezdés napját viszi', () {
    // 2026. 07. 20. hétfő, 07. 26. vasárnap — a hét két szélső napja a kényes,
    // mert a `weekday` 1-től 7-ig megy, a napkódok tömbje meg 0-tól.
    final monday = DateTime(2026, 7, 20, 14, 30);
    final sunday = DateTime(2026, 7, 26, 9);

    expect(rruleFor(Recurrence.none, monday), isNull);
    expect(rruleFor(Recurrence.daily, monday), 'FREQ=DAILY');
    expect(rruleFor(Recurrence.weekly, monday), 'FREQ=WEEKLY;BYDAY=MO');
    expect(rruleFor(Recurrence.weekly, sunday), 'FREQ=WEEKLY;BYDAY=SU');
    expect(rruleFor(Recurrence.yearly, monday), 'FREQ=YEARLY');

    // A hét összes napja a helyes kódot kapja — a sorrend elcsúszása így nem
    // maradhat észrevétlen.
    expect(
      [
        for (var day = 20; day <= 26; day++)
          rruleFor(Recurrence.weekly, DateTime(2026, 7, day)),
      ],
      [
        'FREQ=WEEKLY;BYDAY=MO',
        'FREQ=WEEKLY;BYDAY=TU',
        'FREQ=WEEKLY;BYDAY=WE',
        'FREQ=WEEKLY;BYDAY=TH',
        'FREQ=WEEKLY;BYDAY=FR',
        'FREQ=WEEKLY;BYDAY=SA',
        'FREQ=WEEKLY;BYDAY=SU',
      ],
    );
  });

  test('ismétlődő esemény: a natív oldal megkapja a szabályt', () async {
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

    final start = DateTime(2026, 7, 20, 18);
    await createEvent(
      title: 'Edzés',
      start: start,
      end: start.add(const Duration(hours: 1)),
      rrule: rruleFor(Recurrence.weekly, start),
    );

    expect(
      (sent!.arguments as Map)['rrule'],
      'FREQ=WEEKLY;BYDAY=MO',
    );
  });

  test('a natív oldalról érkező sorozat ismétlődőnek látszik', () {
    final at = DateTime(2026, 7, 20, 18);
    final single = parseEvent(_raw(begin: at.millisecondsSinceEpoch));
    final series = parseEvent(
      _raw(begin: at.millisecondsSinceEpoch, rrule: 'FREQ=WEEKLY;BYDAY=MO'),
    );

    expect(single.recurring, isFalse);
    expect(series.recurring, isTrue);
    // A szerkesztés ezt írja vissza változatlanul.
    expect(series.rrule, 'FREQ=WEEKLY;BYDAY=MO');
  });

  test('a résztvevők névsora átjön, üresen és hiányzó kulcsnál sem törik', () {
    final begin = DateTime(2026, 7, 23, 14).millisecondsSinceEpoch;
    // Így küldi a natív oldal (lásd CalendarQuery.queryAcceptedGuests): csak
    // azok, akik elfogadták, a saját fiókunk nélkül.
    expect(
      parseEvent({..._raw(begin: begin), 'guests': ['Anna', 'bela@pelda.hu']}).guests,
      ['Anna', 'bela@pelda.hu'],
    );
    // A régi/üres válasz nem hibázhat: a kártya ilyenkor nem ír ki semmit.
    expect(parseEvent(_raw(begin: begin)).guests, isEmpty);
    expect(parseEvent({..._raw(begin: begin), 'guests': ['  ']}).guests, isEmpty);
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
