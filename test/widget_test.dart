import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_calendar/app.dart';
import 'package:my_calendar/core/notifications.dart';
import 'package:my_calendar/features/auth/auth_controller.dart';
import 'package:my_calendar/features/calendar/calendar_service.dart';
import 'package:my_calendar/features/calendar/event_categories.dart';
import 'package:my_calendar/features/calendar/event_groups.dart';
import 'package:my_calendar/features/help/guide.dart';
import 'package:my_calendar/features/settings/settings_screen.dart';
import 'package:my_calendar/features/settings/wallpaper.dart';
import 'package:my_calendar/features/workouts/motivation.dart';
import 'package:my_calendar/core/prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A providerek felülírásával az auth-guard Firebase és Google API nélkül
/// tesztelhető.
Widget _appWith(AsyncValue<AuthUser?> user) => ProviderScope(
  overrides: [
    currentUserProvider.overrideWithValue(user),
    upcomingEventsProvider.overrideWithValue(
      const AsyncValue.data(<CalendarEvent>[]),
    ),
  ],
  child: const MyCalendarApp(),
);

/// Átvált a megadott fülre az alsó navigációs sávon.
Future<void> _goTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await tester.pumpAndSettle();
}

void main() {
  // Az app a mentett beállításokat a main-ben tölti be — a teszt ugyanezt
  // csinálja, memóriában.
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // A bemutatót „látottnak" jelöljük: első indításkor magától felugrana, és
    // minden más teszt elől eltakarná a képernyőt. A saját tesztje törli.
    SharedPreferences.setMockInitialValues({'guideSeen': 'true'});
    await initPrefs();
    // Az értesítés-plugin natív oldala nincs a tesztben: a pipálás
    // újraütemezné az esti kérdéseket, ezt nyeljük el.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dexterous.com/flutter/local_notifications'),
          (_) async => null,
        );
    // A naptárnézet a hónap eseményeit a natív csatornán kéri — üres naptárt
    // adunk vissza, hogy a rács adat nélkül is felépüljön.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('mycalendar/device_calendar'),
          (_) async => <Object?>[],
        );
  });

  testWidgets('kijelentkezve a login képernyőre terel', (tester) async {
    await tester.pumpWidget(_appWith(const AsyncValue.data(null)));
    await tester.pumpAndSettle();
    expect(find.text('Bejelentkezés Google-fiókkal'), findsOneWidget);
  });

  testWidgets('bejelentkezve a főképernyő és az alsó navigáció látszik', (
    tester,
  ) async {
    await tester.pumpWidget(_appWith(const AsyncValue.data(AuthUser('Teszt'))));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Események'), findsOneWidget);
    expect(find.text('Szabad két hét'), findsOneWidget);
    for (final label in [
      'Események',
      'Naptár',
      'Beosztás',
      'Edzésnapló',
      'Beállítások',
    ]) {
      expect(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(label),
        ),
        findsOneWidget,
      );
    }
  });

  testWidgets('a naptár fül a hónapos rácsot mutatja', (tester) async {
    await tester.pumpWidget(_appWith(const AsyncValue.data(AuthUser('Teszt'))));
    await tester.pumpAndSettle();
    await _goTab(tester, 'Naptár');
    expect(find.widgetWithText(AppBar, 'Naptár'), findsOneWidget);
    // A hét napjainak fejléce a naptárrács tetején — a valódi naptárnézet
    // felépült (nem placeholder).
    expect(find.text('Sze'), findsOneWidget);

    // A rendszer vissza gombja nem lép ki az appból, hanem a főképernyőre visz.
    final popped = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(popped, isTrue);
    expect(find.widgetWithText(AppBar, 'Események'), findsOneWidget);
  });

  testWidgets('a naptár fejlécéből elérhető és megnyílik a kategória-kezelő', (
    tester,
  ) async {
    await tester.pumpWidget(_appWith(const AsyncValue.data(AuthUser('Teszt'))));
    await tester.pumpAndSettle();
    await _goTab(tester, 'Naptár');

    // A kategóriák önálló belépési pontja a fejlécben van — nem kell hozzá
    // előbb eseményt megnyitni.
    final action = find.byTooltip('Kategóriák');
    expect(action, findsOneWidget);

    await tester.tap(action);
    await tester.pumpAndSettle();
    // A kezelő lap (esemény nélkül) létrehozással.
    expect(find.text('Naptárkategóriák'), findsOneWidget);
    expect(find.text('Új kategória'), findsOneWidget);
  });

  testWidgets('oldalra húzva vált a naptár hónapja', (tester) async {
    await tester.pumpWidget(_appWith(const AsyncValue.data(AuthUser('Teszt'))));
    await tester.pumpAndSettle();
    await _goTab(tester, 'Naptár');

    final now = DateTime.now();
    final current = DateTime(now.year, now.month);
    String header(DateTime m) => '${m.year}. ${monthName(m.month)}';
    expect(find.text(header(current)), findsOneWidget);

    // Jobbról balra húzás: következő hónap. A húzás a lista látható felső
    // részéről indul — a rács alja a teszt-ablakban a hajtás alá lóg.
    await tester.fling(find.byType(ListView), const Offset(-400, 0), 1200);
    await tester.pumpAndSettle();
    final next = DateTime(current.year, current.month + 1);
    expect(find.text(header(next)), findsOneWidget);

    // Balról jobbra húzás: vissza az előzőre.
    await tester.fling(find.byType(ListView), const Offset(400, 0), 1200);
    await tester.pumpAndSettle();
    expect(find.text(header(current)), findsOneWidget);
  });

  testWidgets('a beállítások fülön a fiók és a kijelentkezés is ott van', (
    tester,
  ) async {
    await tester.pumpWidget(_appWith(const AsyncValue.data(AuthUser('Teszt'))));
    await tester.pumpAndSettle();
    await _goTab(tester, 'Beállítások');
    expect(find.text('Teszt'), findsOneWidget);
    expect(find.text('Kijelentkezés'), findsOneWidget);
  });

  testWidgets('a beállított színkészlet az appra is érvényes', (tester) async {
    await tester.pumpWidget(_appWith(const AsyncValue.data(AuthUser('Teszt'))));
    await tester.pumpAndSettle();
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.system,
    );

    await _goTab(tester, 'Beállítások');
    await tester.tap(find.text('Sötét'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );
  });

  test(
    'az időválasztó alapból billentyűzetes, és a választás megmarad',
    () async {
      addTearDown(() => prefs.remove('timePickerKeyboard'));
      // Mentett érték nélkül a billentyűzetes mód az alapértelmezés.
      final first = ProviderContainer();
      addTearDown(first.dispose);
      expect(first.read(timeKeyboardProvider), isTrue);

      await first.read(timeKeyboardProvider.notifier).set(false);

      // Új munkamenet (friss container) a mentett értéket olvassa vissza.
      final reopened = ProviderContainer();
      addTearDown(reopened.dispose);
      expect(reopened.read(timeKeyboardProvider), isFalse);
    },
  );

  test(
    'az értesítés-kapcsolók alapból be vannak kapcsolva, és megmaradnak',
    () async {
      addTearDown(() => prefs.remove(hourBeforeKey));
      // Mentett érték nélkül mindhárom kapcsoló be van kapcsolva.
      final first = ProviderContainer();
      addTearDown(first.dispose);
      expect(first.read(notificationsProvider), (
        dayBefore: true,
        hourBefore: true,
        workout: true,
      ));

      await first
          .read(notificationsProvider.notifier)
          .set(hourBeforeKey, false);
      expect(first.read(notificationsProvider).hourBefore, isFalse);

      // Új munkamenet (friss container) a mentett értéket olvassa vissza.
      final reopened = ProviderContainer();
      addTearDown(reopened.dispose);
      expect(reopened.read(notificationsProvider).hourBefore, isFalse);
      expect(reopened.read(notificationsProvider).dayBefore, isTrue);
    },
  );

  testWidgets('kategória egyedi színnel: a csúszkák a palettán kívülre visznek', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1080, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(() => prefs.remove('eventCategories'));

    await tester.pumpWidget(_appWith(const AsyncValue.data(AuthUser('Teszt'))));
    await tester.pumpAndSettle();
    await _goTab(tester, 'Naptár');
    await tester.tap(find.byTooltip('Kategóriák'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Új kategória'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Név'), 'Egyetem');
    // Alapból csak a paletta látszik — a csúszkák az „egyedi szín" alatt vannak.
    expect(find.byType(Slider), findsNothing);
    await tester.tap(find.byTooltip('Egyedi szín'));
    await tester.pumpAndSettle();
    expect(find.byType(Slider), findsNWidgets(3));

    // Az árnyalat csúszkát elhúzva a szín kikerül az alapszínek közül.
    await tester.drag(find.byType(Slider).first, const Offset(120, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Létrehozás'));
    await tester.pumpAndSettle();

    final saved = jsonDecode(prefs.getString('eventCategories')!) as List;
    final color = (saved.single as Map)['color'] as int;
    expect(
      [for (final c in categoryColors) c.toARGB32()],
      isNot(contains(color)),
      reason: 'az egyedi szín nem lehet a paletta egyik alapszíne',
    );
  });

  testWidgets('beosztás: tétel felvitele, napi és heti nézet', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1080, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(() => prefs.remove('schedule'));

    await tester.pumpWidget(_appWith(const AsyncValue.data(AuthUser('Teszt'))));
    await tester.pumpAndSettle();
    await _goTab(tester, 'Beosztás');
    expect(find.text('Még üres a beosztásod'), findsOneWidget);

    await tester.tap(find.text('Első tétel felvétele'));
    await tester.pumpAndSettle();
    // A lap a MAI napra nyílik: a mentett tétel ezért a napi nézetben rögtön
    // látszik, bármelyik napon fut a teszt.
    await tester.enterText(
      find.widgetWithText(TextField, 'Mi ez?'),
      'Közgazdaságtan előadás',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mentés'));
    await tester.pumpAndSettle();

    // Napi nézet: a tétel a kezdésével és a hosszával.
    expect(find.text('Közgazdaságtan előadás'), findsOneWidget);
    expect(find.text('8:00'), findsOneWidget);
    expect(find.textContaining('1 tétel · 1 óra 30 perc'), findsOneWidget);

    // Heti nézetben ugyanaz a tétel a rácsban.
    await tester.tap(find.text('Hét'));
    await tester.pumpAndSettle();
    expect(find.text('Közgazdaságtan előadás'), findsOneWidget);
    expect(find.text('8:00–9:30'), findsOneWidget);
  });

  testWidgets('beosztás: oldalra húzva lapoz napot és hetet', (tester) async {
    // VALÓDI telefonszélesség (360 dp), nem a tesztek tág alapértelmezése: a
    // heti rács csak akkor engedi a lapozó húzást, ha a napok kiférnek — széles
    // felületen ez mindig igaz lenne, és a teszt elnézné a hibát.
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(() => prefs.remove('schedule'));
    // Minden napra egy tétel: a napi nézet a hét bármely napján mutat valamit.
    await prefs.setString(
      'schedule',
      '{"abWeeks":false,"groups":[],"entries":[${[
        for (var day = 1; day <= 7; day++)
          '{"id":"$day","weekday":$day,"start":480,"end":570,'
              '"title":"Reggeli műszak","week":null,"note":"","groupId":null}',
      ].join(',')}]}',
    );

    await tester.pumpWidget(_appWith(const AsyncValue.data(AuthUser('Teszt'))));
    await tester.pumpAndSettle();
    await _goTab(tester, 'Beosztás');

    // Napi nézet: balra húzva holnap, vissza jobbra megint ma.
    expect(find.textContaining('Ma · '), findsOneWidget);
    await tester.fling(find.byType(ListView), const Offset(-400, 0), 1200);
    await tester.pumpAndSettle();
    expect(find.textContaining('Ma · '), findsNothing);
    await tester.fling(find.byType(ListView), const Offset(400, 0), 1200);
    await tester.pumpAndSettle();
    expect(find.textContaining('Ma · '), findsOneWidget);

    // Heti nézet: a húzás egész hetet lapoz — a rácson kezdve is (ott nincs
    // vízszintes görgetés, ami elnyelné). A mai héten állva nincs „Ugrás a mai
    // napra" gomb; egy hetet lapozva megjelenik.
    await tester.tap(find.text('Hét'));
    await tester.pumpAndSettle();
    final today = find.byTooltip('Ugrás a mai napra');
    expect(today, findsNothing);
    await tester.fling(find.text('8:00'), const Offset(-400, 0), 1200);
    await tester.pumpAndSettle();
    expect(today, findsOneWidget);
  });

  testWidgets('beosztás: A/B hétre váltva mindkét héten megmarad a tétel', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1080, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(() => prefs.remove('schedule'));
    // Minden napra egy tétel, hogy a napi nézet a hét bármely napján mutasson
    // valamit.
    await prefs.setString(
      'schedule',
      '{"abWeeks":false,"groups":[],"entries":[${[
        for (var day = 1; day <= 7; day++)
          '{"id":"$day","weekday":$day,"start":480,"end":570,'
              '"title":"Reggeli műszak","week":null,"note":"","groupId":null}',
      ].join(',')}]}',
    );

    await tester.pumpWidget(_appWith(const AsyncValue.data(AuthUser('Teszt'))));
    await tester.pumpAndSettle();
    await _goTab(tester, 'Beosztás');
    // Sima heti beosztásnál nincs A/B jelvény.
    expect(find.textContaining('HÉT · MOST'), findsNothing);

    await tester.tap(find.byTooltip('A beosztás műveletei'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Váltás A és B hetesre'));
    await tester.pumpAndSettle();

    // A jelvény a most futó hetet mutatja, a tétel pedig megmaradt.
    expect(find.textContaining('HÉT · MOST'), findsOneWidget);
    expect(find.text('Reggeli műszak'), findsOneWidget);

    // A következő hét már a másik betűjelű (a jelvény nem a most futó hetet
    // mutatja), a tétel viszont ott is szerepel — minden napon egy.
    await tester.tap(find.text('Hét'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Következő hét'));
    await tester.pumpAndSettle();
    expect(find.textContaining('HÉT · MOST'), findsNothing);
    expect(find.text('Reggeli műszak'), findsWidgets);
  });

  testWidgets('edzésterv felvitele és megjelenítése', (tester) async {
    // Magas ablak, hogy a lista minden mezője megépüljön — így nem kell
    // görgetni a teszt közben.
    await tester.binding.setSurfaceSize(const Size(1080, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // A teszt VALÓDI tervet ment a beállításokba — takarítás nélkül a következő
    // tesztek már nem a „még nincs terved" állapottal indulnának.
    addTearDown(() async {
      await prefs.remove('workoutPlans');
      await prefs.remove('activeWorkoutPlan');
      await prefs.remove('workoutProgress');
    });

    await tester.pumpWidget(_appWith(const AsyncValue.data(AuthUser('Teszt'))));
    await tester.pumpAndSettle();
    await _goTab(tester, 'Edzésnapló');
    expect(find.text('Még nincs edzésterved'), findsOneWidget);

    await tester.tap(find.text('Edzésterv létrehozása'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'A terv neve'),
      'Erő',
    );
    // Alapból 3 nap, egyet levéve 2.
    await tester.tap(find.byTooltip('Kevesebb nap'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('0-0')), 'mell, tricepsz');
    await tester.enterText(find.byKey(const ValueKey('0-1')), 'hát, bicepsz');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Edzésterv mentése'));
    await tester.pumpAndSettle();

    expect(find.text('Erő'), findsOneWidget);
    expect(
      find.text('Sima heti terv · ezen a héten 0/2 megvan'),
      findsOneWidget,
    );
    expect(find.text('1. NAP'), findsOneWidget);
    expect(find.text('mell, tricepsz'), findsOneWidget);
  });

  testWidgets('a heti edzésnapok száma 1 és 14 között állítható', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1080, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_appWith(const AsyncValue.data(AuthUser('Teszt'))));
    await tester.pumpAndSettle();
    await _goTab(tester, 'Edzésnapló');
    await tester.tap(find.text('Edzésterv létrehozása'));
    await tester.pumpAndSettle();

    // A napok számát a beírómezők jelenléte mutatja (kulcs: `hét-nap`).
    // Alapból 3 nap; a határon túli koppintás nem tesz semmit.
    for (var i = 0; i < 5; i++) {
      await tester.tap(find.byTooltip('Kevesebb nap'));
      await tester.pumpAndSettle();
    }
    expect(find.byKey(const ValueKey('0-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('0-1')), findsNothing);

    for (var i = 0; i < 20; i++) {
      await tester.tap(find.byTooltip('Több nap'));
      await tester.pumpAndSettle();
    }
    expect(find.byKey(const ValueKey('0-13')), findsOneWidget);
    expect(find.byKey(const ValueKey('0-14')), findsNothing);
  });

  testWidgets('a mai edzés csak megerősítés után kap pipát', (tester) async {
    await prefs.setString(
      'workoutPlans',
      '[{"id":"p1","name":"Erő","weeks":[["mell, tricepsz","hát, bicepsz"]]}]',
    );
    await prefs.setString('activeWorkoutPlan', 'p1');
    addTearDown(() async {
      await prefs.remove('workoutPlans');
      await prefs.remove('activeWorkoutPlan');
      await prefs.remove('workoutProgress');
    });

    await tester.pumpWidget(_appWith(const AsyncValue.data(AuthUser('Teszt'))));
    await tester.pumpAndSettle();
    await _goTab(tester, 'Edzésnapló');
    expect(
      find.text('Sima heti terv · ezen a héten 0/2 megvan'),
      findsOneWidget,
    );

    // Amíg a hét nincs meg, a gondolkodtató kártya látszik az aktuális
    // párossal — a fülre lépés forgatott egyet a szövegeken.
    final reflection = reflectionFor(DateTime.now(), spin: motivationSpin.value);
    expect(find.text('MIÉRT ÉRI MEG MA?'), findsOneWidget);
    expect(find.text(reflection.gain), findsOneWidget);
    expect(find.text(reflection.cost), findsOneWidget);

    // Elnavigálva és visszalépve MÁS szöveg jár: a fül a héjban életben marad,
    // a kártya mégis frissül.
    await _goTab(tester, 'Események');
    await _goTab(tester, 'Edzésnapló');
    expect(find.text(reflection.gain), findsNothing);
    expect(find.text(reflection.cost), findsNothing);
    expect(
      find.text(reflectionFor(DateTime.now(), spin: motivationSpin.value).gain),
      findsOneWidget,
    );

    // Koppintásra nem történik semmi — csak hosszú nyomásra kérdez.
    await tester.tap(find.text('mell, tricepsz'));
    await tester.pumpAndSettle();
    expect(find.text('Mi lett ezzel a nappal?'), findsNothing);

    // Mégsem: marad pipa nélkül.
    await tester.longPress(find.text('mell, tricepsz'));
    await tester.pumpAndSettle();
    expect(find.text('Mi lett ezzel a nappal?'), findsOneWidget);
    await tester.tap(find.text('Mégsem'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check_circle), findsNothing);

    // Megerősítve viszont kipipálódik, és dicséret jár érte.
    await tester.longPress(find.text('mell, tricepsz'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Megvolt'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(
      find.text('Sima heti terv · ezen a héten 1/2 megvan'),
      findsOneWidget,
    );
    expect(
      find.text(
        praiseFor(
          done: 1,
          total: 2,
          day: DateTime.now(),
          spin: motivationSpin.value,
        ),
      ),
      findsOneWidget,
    );
    // A SnackBar magától eltűnik — a lejáratát is lepörgetjük, hogy ne
    // maradjon függő időzítő a teszt végén.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    // A kipipált nap visszaállítható: a kérdés újranyílik, és ott már van
    // visszavonás — utána a nap megint nyitott.
    await tester.longPress(find.text('mell, tricepsz'));
    await tester.pumpAndSettle();
    expect(find.text('Mi lett ezzel a nappal?'), findsOneWidget);
    await tester.tap(find.text('Visszaállítás'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check_circle), findsNothing);
    expect(
      find.text('Sima heti terv · ezen a héten 0/2 megvan'),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('teljes hét sorozatot indít és jelvényt mutat', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1080, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // Egynapos terv, hogy egyetlen pipával teljes legyen a hét.
    await prefs.setString(
      'workoutPlans',
      '[{"id":"s1","name":"Napi","weeks":[["teljes test"]]}]',
    );
    await prefs.setString('activeWorkoutPlan', 's1');
    addTearDown(() async {
      await prefs.remove('workoutPlans');
      await prefs.remove('activeWorkoutPlan');
      await prefs.remove('workoutProgress');
      await prefs.remove('workoutStreak');
    });

    await tester.pumpWidget(_appWith(const AsyncValue.data(AuthUser('Teszt'))));
    await tester.pumpAndSettle();
    await _goTab(tester, 'Edzésnapló');
    // Kezdéskor nincs sorozat, nincs jelvény.
    expect(find.textContaining('hét zsinórban'), findsNothing);

    await tester.longPress(find.text('teljes test'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Megvolt'));
    await tester.pumpAndSettle();

    // A hét teljes lett → 1 hetes sorozat indul, a jelvény megjelenik.
    expect(find.text('1 hét zsinórban'), findsOneWidget);
    // A lejáró SnackBar időzítőjét lepörgetjük.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('első indításkor felugrik a bemutató, és kihagyható', (
    tester,
  ) async {
    await prefs.remove('guideSeen');
    addTearDown(() => prefs.setString('guideSeen', 'true'));

    await tester.pumpWidget(_appWith(const AsyncValue.data(AuthUser('Teszt'))));
    await tester.pumpAndSettle();
    expect(find.text(guideTopics.first.title), findsOneWidget);
    expect(find.text('1 / ${guideTopics.length}'), findsOneWidget);

    // Lépésenként tovább.
    await tester.tap(find.text('Tovább'));
    await tester.pumpAndSettle();
    expect(find.text(guideTopics[1].title), findsOneWidget);

    // Kihagyva bezárul, és többé nem jön elő magától.
    await tester.tap(find.text('Kihagyom'));
    await tester.pumpAndSettle();
    expect(find.text(guideTopics[1].title), findsNothing);
    expect(guideSeen, isTrue);

    await tester.pumpWidget(_appWith(const AsyncValue.data(AuthUser('Más'))));
    await tester.pumpAndSettle();
    expect(find.text(guideTopics.first.title), findsNothing);
  });

  testWidgets('a naptárak külön aloldalon nyílnak a beállításokból', (
    tester,
  ) async {
    await tester.pumpWidget(_appWith(const AsyncValue.data(AuthUser('Teszt'))));
    await tester.pumpAndSettle();
    await _goTab(tester, 'Beállítások');

    // A naptárlista NEM a beállítások lapján van, csak a bejárat.
    final entry = find.text('Megjelenő naptárak');
    await tester.scrollUntilVisible(entry, 400);
    // A megtalált sor még a lista alsó gyorsítótárában (az alsó sáv alatt)
    // állhat — ez húzza be ténylegesen a képre.
    await tester.ensureVisible(entry);
    await tester.pumpAndSettle();
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Naptárak'), findsOneWidget);
  });

  group('háttérkép', () {
    // A legkisebb érvényes PNG: a kép tartalma mindegy, létezőnek kell lennie.
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQ'
      'DwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
    );
    late File file;

    setUp(() async {
      file = File('${Directory.systemTemp.path}/mycalendar_wallpaper.png');
      await file.writeAsBytes(png);
    });
    tearDown(() async {
      if (file.existsSync()) await file.delete();
      await prefs.remove('wallpaper');
    });

    testWidgets('beállítva a lapok mögé kerül, és átlátszóvá teszi őket', (
      tester,
    ) async {
      await prefs.setString('wallpaper', file.path);
      await tester.pumpWidget(
        _appWith(const AsyncValue.data(AuthUser('Teszt'))),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Wallpaper), findsOneWidget);
      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.theme?.scaffoldBackgroundColor, Colors.transparent);
      expect(app.darkTheme?.scaffoldBackgroundColor, Colors.transparent);
    });

    testWidgets('a közben eltűnt fájlt eldobjuk, nem lesz üres a felület', (
      tester,
    ) async {
      // Valódi fájlműveletet a teszt törzsében nem szabad megvárni (a
      // testWidgets hamis órája nem hajtja az I/O-t) — elég egy nem létező út.
      await prefs.setString('wallpaper', '${file.path}.nincs');

      await tester.pumpWidget(
        _appWith(const AsyncValue.data(AuthUser('Teszt'))),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Wallpaper), findsNothing);
      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.theme?.scaffoldBackgroundColor, isNot(Colors.transparent));
    });
  });

  testWidgets('a súgó a beállításokból nyílik és újraindítja a bemutatót', (
    tester,
  ) async {
    await tester.pumpWidget(_appWith(const AsyncValue.data(AuthUser('Teszt'))));
    await tester.pumpAndSettle();
    await _goTab(tester, 'Beállítások');

    // A súgó a lista alján van — előbb odagörgetünk. Az `ensureVisible` a
    // teljes sort behozza: a görgetés magában a képernyő aljára is teheti,
    // ahol a koppintás középpontja már kilóg a nézetből.
    final entry = find.text('Súgó és útmutató');
    await tester.scrollUntilVisible(entry, 400);
    await tester.ensureVisible(entry);
    await tester.pumpAndSettle();
    await tester.tap(entry);
    await tester.pumpAndSettle();
    // Minden téma szakaszként ott van, lenyitva a leírásával.
    expect(find.text(guideTopics.first.title), findsOneWidget);
    await tester.tap(find.text(guideTopics.first.title));
    await tester.pumpAndSettle();
    expect(find.text(guideTopics.first.body), findsOneWidget);

    // A bemutató innen újranézhető.
    await tester.tap(find.text('Bemutató újranézése'));
    await tester.pumpAndSettle();
    expect(find.text('1 / ${guideTopics.length}'), findsOneWidget);
  });

  testWidgets('töltés közben nem dob a loginra', (tester) async {
    await tester.pumpWidget(_appWith(const AsyncValue.loading()));
    await tester.pump();
    expect(find.text('Bejelentkezés Google-fiókkal'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
