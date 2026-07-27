import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_calendar/features/calendar/calendar_service.dart';

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
    // A @ nélküli darab nem cím, az üres mezőből pedig nincs meghívott — ez
    // dönti el, hogy sima mentés lesz-e vagy a Naptár szerkesztője nyílik.
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
