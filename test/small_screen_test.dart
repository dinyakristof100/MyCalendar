import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_calendar/app.dart';
import 'package:my_calendar/core/prefs.dart';
import 'package:my_calendar/features/auth/auth_controller.dart';
import 'package:my_calendar/features/calendar/calendar_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A legszűkebb kijelző, amit még kiszolgálunk: 320x568 logikai pixel (4"
/// készülék). Aki 5 hüvelykes telefonon nézi (jellemzően 360x640), az ennél
/// szélesebb — vagyis ami itt kifér, ott is kifér.
///
/// A többi teszt a 800x600-as alapértelmezett felületen fut, ami SZÉLESEBB, mint
/// bármelyik telefon: a kifutó feliratokat ezért egyik sem vette észre.
///
/// Ez a teszt szándékosan szigorúbb a valóságnál: a `flutter test`
/// betűkészletében minden glifa a betűméret szélességű négyzet, vagyis a szöveg
/// kb. kétszer olyan széles, mint a készüléken a Roboto. A ráhagyás nem kerül
/// semmibe — a javítások (zsugorítás, új sorba tördelés) elég helynél nem
/// tesznek semmit.
const _narrow = Size(320, 568);

/// Az emberek jó része nagyobb rendszerbetűvel használja a telefont — a felirat
/// ilyenkor is maradjon a gombon.
const _bigFont = 1.4;

Widget _app() => ProviderScope(
  overrides: [
    currentUserProvider.overrideWithValue(
      const AsyncValue.data(AuthUser('Teszt Elek', email: 'teszt@pelda.hu')),
    ),
    upcomingEventsProvider.overrideWithValue(
      AsyncValue.data([
        CalendarEvent(
          id: '1',
          // Hosszú cím: a kártyán ennek is muszáj elférnie (tördelve vagy
          // levágva), nem szabad kifutnia.
          title: 'Éves fogorvosi kontrollvizsgálat és szájhigiénia',
          at: DateTime.now().add(const Duration(hours: 3)),
          end: DateTime.now().add(const Duration(hours: 4)),
          allDay: false,
        ),
      ]),
    ),
  ],
  child: const MyCalendarApp(),
);

/// A kifutó tartalom (RenderFlex overflow) kivételként érkezik — ez a
/// visszajelzés arról, hogy egy felirat „összetört" a kis kijelzőn.
/// Ha ez elhasal, a hibás widget kiderítéséhez kommentezd ki ezt a hívást: a
/// keretrendszer az el nem kapott hibánál kiírja a „relevant error-causing
/// widget" sort is.
void _expectFits(WidgetTester tester, String where) {
  expect(
    tester.takeException(),
    isNull,
    reason: 'kifutó tartalom itt: $where (320 px széles kijelzőn)',
  );
}

Future<void> _pumpNarrow(WidgetTester tester, {double textScale = 1.0}) async {
  await tester.binding.setSurfaceSize(_narrow);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(() {
    tester.binding.setSurfaceSize(null);
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
  await tester.pumpWidget(_app());
  await tester.pumpAndSettle();
}

Future<void> _goTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await tester.pumpAndSettle();
}

/// A/B hetes beosztás minden napra egy hosszú című tétellel, hétfőn egy
/// átfedővel — a keskeny oszlopban két blokk osztozik.
String _scheduleJson() {
  final entries = [
    for (var day = 1; day <= 7; day++)
      '{"id":"$day","weekday":$day,"start":480,"end":570,'
          '"title":"Közgazdaságtan előadás","week":null,'
          '"note":"B/2 terem, Nagy Béla","groupId":"g1"}',
    '{"id":"x","weekday":1,"start":510,"end":600,"title":"Konzultáció",'
        '"week":0,"note":"","groupId":null}',
  ];
  return '{"abWeeks":true,"groups":[{"id":"g1","name":"Előadás",'
      '"color":4285764297}],"entries":[${entries.join(',')}]}';
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({'guideSeen': 'true'});
    await initPrefs();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dexterous.com/flutter/local_notifications'),
          (_) async => null,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('mycalendar/device_calendar'),
          // A meghívott-javaslat csipeszeihez szándékosan hosszú cím: annak is
          // el kell férnie a legszűkebb kijelzőn.
          (call) async => switch (call.method) {
            'knownGuests' => const [
              'nagyon.hosszu.nevu.kollega@egy-hosszu-ceges-domain.hu',
              'anna@pelda.hu',
            ],
            _ => <Object?>[],
          },
        );
  });

  testWidgets('az öt fül kifér a legszűkebb kijelzőn', (tester) async {
    await _pumpNarrow(tester);
    _expectFits(tester, 'Események fül');

    for (final tab in ['Naptár', 'Beosztás', 'Edzésnapló', 'Beállítások']) {
      await _goTab(tester, tab);
      _expectFits(tester, '$tab fül');
    }
  });

  testWidgets('az esemény részletei és a gombjai kiférnek', (tester) async {
    await _pumpNarrow(tester);
    // Két helyen szerepel: a következő esemény kiemelt kártyáján és a napok
    // listájában. Az elsőre koppintunk.
    await tester.tap(find.textContaining('fogorvosi').first);
    await tester.pumpAndSettle();
    // A három akció (Szerkesztés, Meghívás, Törlés) egy sorban a legszűkebb
    // hely az appban.
    expect(find.text('Szerkesztés'), findsOneWidget);
    expect(find.text('Meghívás'), findsOneWidget);
    _expectFits(tester, 'esemény részletei');

    await tester.tap(find.text('Meghívás'));
    await tester.pumpAndSettle();
    _expectFits(tester, 'meghívás párbeszéd');
  });

  testWidgets('az esemény-űrlap kifér', (tester) async {
    await _pumpNarrow(tester);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    _expectFits(tester, 'új esemény űrlap');

    // Meghívottal a tájékoztató sáv is megjelenik — az is elfér.
    await tester.enterText(
      find.widgetWithText(TextField, 'Meghívottak'),
      'anna@pelda.hu',
    );
    await tester.pumpAndSettle();
    _expectFits(tester, 'új esemény űrlap meghívottal');
  });

  testWidgets('az első indításkori bemutató kifér', (tester) async {
    // A bemutató az, amit egy új felhasználó ELŐSZÖR lát — ha valami itt törik
    // össze, az az első benyomás. A lépésjelző pöttyök száma a témákkal nő,
    // ezért érdemes végignézni mindet.
    await prefs.remove('guideSeen');
    addTearDown(() => prefs.setString('guideSeen', 'true'));

    await _pumpNarrow(tester);
    _expectFits(tester, 'bemutató első lapja');

    while (find.text('Tovább').evaluate().isNotEmpty) {
      await tester.tap(find.text('Tovább'));
      await tester.pumpAndSettle();
      _expectFits(tester, 'bemutató egyik lapja');
    }
    expect(find.text('Kezdhetjük!'), findsOneWidget);
  });

  testWidgets('az edzésterv és az űrlapja kifér', (tester) async {
    // Hosszú napleírás: a nap kártyáján ennek is el kell férnie.
    await prefs.setString(
      'workoutPlans',
      '[{"id":"p1","name":"Erő és állóképesség","weeks":'
          '[["mell, tricepsz, váll","hát, bicepsz, alkar"]]}]',
    );
    await prefs.setString('activeWorkoutPlan', 'p1');
    addTearDown(() async {
      await prefs.remove('workoutPlans');
      await prefs.remove('activeWorkoutPlan');
      await prefs.remove('workoutProgress');
    });

    await _pumpNarrow(tester);
    await _goTab(tester, 'Edzésnapló');
    _expectFits(tester, 'edzésterv nézet');

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    _expectFits(tester, 'edzésterv űrlap');
  });

  testWidgets('az egyedi színválasztó kifér a legszűkebb kijelzőn', (
    tester,
  ) async {
    await _pumpNarrow(tester);
    await _goTab(tester, 'Naptár');
    await tester.tap(find.byTooltip('Kategóriák'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Új kategória'));
    await tester.pumpAndSettle();
    _expectFits(tester, 'új kategória párbeszéd');

    // Az egyedi szín három csúszkát nyit — ez a párbeszéd legmagasabb állapota.
    await tester.tap(find.byTooltip('Egyedi szín'));
    await tester.pumpAndSettle();
    expect(find.byType(Slider), findsNWidgets(3));
    _expectFits(tester, 'egyedi színválasztó');
  });

  testWidgets('a beosztás mindkét nézete és az űrlapja kifér', (tester) async {
    // Mind a hét napon van tétel: a heti rács így a legszélesebb (hét oszlop),
    // és a napi nézet is biztosan tartalmas, bármelyik napon fut a teszt.
    await prefs.setString('schedule', _scheduleJson());
    addTearDown(() => prefs.remove('schedule'));

    await _pumpNarrow(tester);
    await _goTab(tester, 'Beosztás');
    _expectFits(tester, 'beosztás napi nézet');

    await tester.tap(find.text('Hét'));
    await tester.pumpAndSettle();
    _expectFits(tester, 'beosztás heti nézet');

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    _expectFits(tester, 'beosztás tétel űrlap');
  });

  testWidgets('nagyobb rendszerbetűvel is kifér minden', (tester) async {
    await _pumpNarrow(tester, textScale: _bigFont);
    _expectFits(tester, 'Események fül nagy betűvel');

    for (final tab in ['Naptár', 'Beosztás', 'Edzésnapló', 'Beállítások']) {
      await _goTab(tester, tab);
      _expectFits(tester, '$tab fül nagy betűvel');
    }

    await _goTab(tester, 'Események');
    // Két helyen szerepel: a következő esemény kiemelt kártyáján és a napok
    // listájában. Az elsőre koppintunk.
    await tester.tap(find.textContaining('fogorvosi').first);
    await tester.pumpAndSettle();
    _expectFits(tester, 'esemény részletei nagy betűvel');
  });
}
