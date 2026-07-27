import 'package:flutter_test/flutter_test.dart';
import 'package:my_calendar/features/calendar/calendar_service.dart';
import 'package:my_calendar/features/calendar/event_csv.dart';

/// Egy valódi nCalendar-mentés kivonata: azonosítósor a fejléc előtt, idézett
/// többsoros jegyzet, egész napos és időpontos sor, CRLF sorvégek.
const _sample =
    'a45408d5d82e77848417a4a21c2f4bac\r\n'
    'Title,Color,AllDay,StartTime,EndTime,RRule,XDate,Alert,Place,UrlEvent,Note\r\n'
    'Csaladi vacsi,0,false,1779699600000,1779724800000,,,[3],,,\r\n'
    'Szent Istvan unnepe,15,true,1755648000000,1755648000000,,,,,,'
    '"Ünnepnapok – Magyarország\r\nMunkaszüneti nap"\r\n';

void main() {
  test('a fejléc előtti sort átugorja, az oszlopokat név szerint olvassa', () {
    final events = parseBackupCsv(_sample);

    expect(events.length, 2);
    expect(events[0].title, 'Csaladi vacsi');
    expect(events[0].allDay, isFalse);
    expect(events[0].at, DateTime.fromMillisecondsSinceEpoch(1779699600000));
    expect(events[0].end, DateTime.fromMillisecondsSinceEpoch(1779724800000));
  });

  test('egész naposnál a nap MEZŐI jönnek át, nem az abszolút időpont', () {
    // 1755648000000 = 2025-08-20 UTC éjfél. Pozitív eltolású zónában (magyar)
    // az időzóna-váltás 19-ére csúsztatná — a naptári napnak 20-ának kell lennie.
    final holiday = parseBackupCsv(_sample)[1];

    expect(holiday.allDay, isTrue);
    expect(holiday.at, DateTime(2025, 8, 20));
    expect(holiday.end, holiday.at);
  });

  test('az idézett mező vesszőt, sortörést és ékezetet is elbír', () {
    expect(
      parseBackupCsv(_sample)[1].description,
      'Ünnepnapok – Magyarország\r\nMunkaszüneti nap',
    );
  });

  test('a kulcs a címre és a kezdésre megy, írásmódtól függetlenül', () {
    final day = DateTime(2025, 8, 20);

    expect(eventKey('  Szülinap ', day, true), eventKey('szülinap', day, true));
    // Az egész napos és az időpontos ugyanakkor kezdődő esemény nem ugyanaz.
    expect(eventKey('X', day, true), isNot(eventKey('X', day, false)));
  });

  test('az export visszaolvasva ugyanazokat a kulcsokat adja', () {
    final events = [
      CalendarEvent(
        id: '1',
        title: 'Munka, délután',
        at: DateTime(2026, 3, 4, 14, 30),
        end: DateTime(2026, 3, 4, 22),
        allDay: false,
        description: 'Sor egy\nsor kettő',
        location: 'Iroda',
      ),
      CalendarEvent(
        id: '2',
        title: 'Karácsony',
        at: DateTime(2026, 12, 25),
        allDay: true,
      ),
    ];

    final back = parseBackupCsv(buildBackupCsv(events));

    expect(
      [for (final e in back) e.key],
      [for (final e in events) eventKey(e.title, e.at, e.allDay)],
    );
    expect(back[0].description, 'Sor egy\nsor kettő');
    expect(back[0].location, 'Iroda');
    expect(back[1].allDay, isTrue);
  });

  test('ismétlődő esemény előfordulásaiból egyetlen sor lesz', () {
    final weekly = [
      for (var day = 1; day <= 3; day++)
        CalendarEvent(
          id: '7', // Az id a SOROZATÉ — minden előfordulás ugyanezt viseli.
          title: 'Edzés',
          at: DateTime(2026, 6, day, 18),
          end: DateTime(2026, 6, day, 19),
          allDay: false,
          rrule: 'FREQ=WEEKLY;BYDAY=MO',
        ),
    ];

    final back = parseBackupCsv(buildBackupCsv(weekly));

    expect(back.length, 1);
    expect(back.single.rrule, 'FREQ=WEEKLY;BYDAY=MO');
  });

  test('a BOM-mal kezdődő fájl fejlécét is megtalálja', () {
    // Windowsos szerkesztők teszik a fájl elejére; ha nem jönne le az első
    // oszlopnévről, a „Title" oszlop nem találna, és minden sor kiesne.
    final events = parseBackupCsv(
      '${String.fromCharCode(0xFEFF)}Title,AllDay,StartTime,EndTime\n'
      'Jó sor,false,1779699600000,1779724800000\n',
    );

    expect(events.single.title, 'Jó sor');
  });

  test('a cím vagy a kezdés nélküli sor kimarad, a többi bejön', () {
    final events = parseBackupCsv(
      'Title,AllDay,StartTime,EndTime\n'
      ',false,1779699600000,1779724800000\n' // nincs cím
      'Nincs időpont,false,,\n'
      'Jó sor,false,1779699600000,1779724800000\n',
    );

    expect([for (final e in events) e.title], ['Jó sor']);
  });
}
