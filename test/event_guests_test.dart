import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_calendar/features/calendar/calendar_service.dart';
import 'package:my_calendar/features/calendar/guest_field.dart';

/// Ahogy a natív oldalról érkezik (lásd `CalendarQuery.queryAttendees`).
Map<String, Object?> _raw({
  String? name,
  String? email,
  String status = 'pending',
  bool organizer = false,
}) => {'name': name, 'email': email, 'status': status, 'organizer': organizer};

void main() {
  test('meghívottak mezője: elválasztók, ismétlődés, szemét', () {
    expect(parseGuestEmails('anna@pelda.hu, bela@pelda.hu; cili@pelda.hu'), [
      'anna@pelda.hu',
      'bela@pelda.hu',
      'cili@pelda.hu',
    ]);
    // Kisbetűsítve egy meghívott — a sorrend a beírás sorrendje marad.
    expect(parseGuestEmails('Bela@Pelda.hu anna@pelda.hu bela@pelda.hu'), [
      'bela@pelda.hu',
      'anna@pelda.hu',
    ]);
    // A @ nélküli darab nem cím, az üres mezőből pedig nincs meghívott — ezen
    // múlik, hogy a mentés egyáltalán hív-e valakit.
    expect(parseGuestEmails('anna, nemcim, '), isEmpty);
    expect(parseGuestEmails('   '), isEmpty);
  });

  test('meghívott válasza: minden ismeretlen státusz „nem válaszolt"', () {
    expect(parseGuest(_raw(status: 'accepted')).status, GuestStatus.accepted);
    expect(parseGuest(_raw(status: 'declined')).status, GuestStatus.declined);
    expect(parseGuest(_raw(status: 'tentative')).status, GuestStatus.tentative);
    // A natív oldal ezt küldi a fel nem ismert kódokra, de a null és egy
    // jövőbeli új érték sem törhet el semmit.
    expect(parseGuest(_raw(status: 'pending')).status, GuestStatus.pending);
    expect(parseGuest(_raw(status: 'valami_uj')).status, GuestStatus.pending);
  });

  test('meghívott neve: név, ha van, egyébként az e-mail cím', () {
    expect(
      parseGuest(_raw(name: 'Anna', email: 'anna@pelda.hu')).label,
      'Anna',
    );
    // A Google csak akkor tud nevet, ha a cím a névjegyekben is szerepel.
    expect(parseGuest(_raw(email: 'anna@pelda.hu')).label, 'anna@pelda.hu');
    // Az üres név ugyanaz, mint a hiányzó — nem írunk ki üres sort.
    expect(
      parseGuest(_raw(name: '  ', email: 'anna@pelda.hu')).label,
      'anna@pelda.hu',
    );
    expect(parseGuest(_raw()).label, '(ismeretlen)');
    expect(parseGuest(_raw(organizer: true)).organizer, isTrue);
  });

  test('javaslatok: részegyezés, a már beírtak nélkül, korlátozva', () {
    const known = [
      'anna@pelda.hu',
      'bela@pelda.hu',
      'anna.kovacs@masik.hu',
      'cili@pelda.hu',
      'dora@pelda.hu',
      'edit@pelda.hu',
    ];

    // Gépelés előtt mind illik — a mező a leggyakoribbakat felajánlja. A
    // korlát nem engedi lenyomni a képernyő aljára a mentés gombot.
    expect(matchingGuests(known, '').length, 5);

    // Részegyezés bárhol a címben: a név elején és a domainben is.
    expect(matchingGuests(known, 'anna'), [
      'anna@pelda.hu',
      'anna.kovacs@masik.hu',
    ]);
    expect(matchingGuests(known, 'masik'), ['anna.kovacs@masik.hu']);

    // Csak az utolsó (épp gépelt) rész számít, a korábbi kész címek nem — és
    // ami már benne van a mezőben, azt nem ajánljuk újra.
    expect(matchingGuests(known, 'bela@pelda.hu, anna'), [
      'anna@pelda.hu',
      'anna.kovacs@masik.hu',
    ]);
    expect(
      matchingGuests(known, 'anna@pelda.hu, '),
      isNot(contains('anna@pelda.hu')),
    );
    expect(matchingGuests(known, 'nincsilyen'), isEmpty);
  });

  test('javaslat választása: csak az épp gépelt címet cseréli', () {
    expect(guestFragment('anna@pelda.hu, be'), 'be');
    expect(guestFragment('anna@pelda.hu, '), '');
    expect(guestFragment(''), '');

    // A korábbi címek érintetlenek, a végén vessző: jöhet a következő.
    expect(
      withGuest('anna@pelda.hu, be', 'bela@pelda.hu'),
      'anna@pelda.hu, bela@pelda.hu, ',
    );
    expect(withGuest('', 'anna@pelda.hu'), 'anna@pelda.hu, ');
    expect(
      withGuest('anna@pelda.hu, ', 'bela@pelda.hu'),
      'anna@pelda.hu, bela@pelda.hu, ',
    );
  });

  testWidgets('a mező gépelésre szűkít, a csipesz beírja a címet', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('mycalendar/device_calendar'),
          (call) async => switch (call.method) {
            'knownGuests' => const ['anna@pelda.hu', 'bela@pelda.hu'],
            _ => <Object?>[],
          },
        );

    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: GuestField(controller: controller, label: 'Meghívottak'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Gépelés előtt mindkettő felajánlva.
    expect(find.text('anna@pelda.hu'), findsOneWidget);
    expect(find.text('bela@pelda.hu'), findsOneWidget);

    // Részegyezésre szűkül...
    await tester.enterText(find.byType(TextField), 'bel');
    await tester.pumpAndSettle();
    expect(find.text('anna@pelda.hu'), findsNothing);

    // ...és a csipesz a gépelt rész helyére írja a címet.
    await tester.tap(find.text('bela@pelda.hu'));
    await tester.pumpAndSettle();
    expect(controller.text, 'bela@pelda.hu, ');
    // Ami már benne van, azt nem ajánlja újra — a másik viszont visszatér.
    expect(find.text('bela@pelda.hu'), findsNothing);
    expect(find.text('anna@pelda.hu'), findsOneWidget);
  });

  test('meghívottak: a lap újranyitása friss választ mutat, nem a cache-t', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    var status = 'pending';
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('mycalendar/device_calendar'),
          (call) async {
            calls++;
            return [_raw(email: 'anna@pelda.hu', status: status)];
          },
        );

    final container = ProviderContainer();
    addTearDown(container.dispose);

    // Ahogy a részletek lapja nézi, amíg nyitva van.
    final open = container.listen(eventGuestsProvider('42'), (_, _) {});
    expect(
      (await container.read(eventGuestsProvider('42').future)).single.status,
      GuestStatus.pending,
    );

    // A lap bezárul, közben megjön a válasz a szinkronnal.
    open.close();
    await Future<void>.delayed(Duration.zero);
    status = 'accepted';

    // Újranyitás: friss lekérdezés, nem a régi eredmény.
    expect(
      (await container.read(eventGuestsProvider('42').future)).single.status,
      GuestStatus.accepted,
    );
    expect(calls, 2);
  });

  test('meglévő eseményhez meghívás: id + címek mennek át', () async {
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

    await addGuests('42', ['anna@pelda.hu', 'bela@pelda.hu']);

    expect(sent!.method, 'addGuests');
    expect(sent!.arguments, {
      'id': '42',
      'guests': ['anna@pelda.hu', 'bela@pelda.hu'],
    });
  });

  test('új esemény meghívottakkal: egy hívás, a címekkel együtt', () async {
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
      title: 'Közös ebéd',
      start: start,
      end: start.add(const Duration(hours: 1)),
      guests: ['anna@pelda.hu', 'bela@pelda.hu'],
    );

    expect(sent!.method, 'createEvent');
    expect(sent!.arguments, {
      'title': 'Közös ebéd',
      'guests': ['anna@pelda.hu', 'bela@pelda.hu'],
      'begin': start.millisecondsSinceEpoch,
      'end': DateTime(2026, 7, 23, 15, 30).millisecondsSinceEpoch,
      'allDay': false,
    });

    // Meghívott nélkül a kulcs sem megy át — a natív oldal ezt veszi „nincs
    // meghívott"-nak, és a többi hívó argumentumai változatlanok.
    await createEvent(title: 'Egyedül', start: start, end: start);
    expect(sent!.arguments, isNot(contains('guests')));
  });
}
