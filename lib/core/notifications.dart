import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;

/// Az app egyetlen értesítés-plugin példánya.
final notifications = FlutterLocalNotificationsPlugin();

/// Az azonosítótér kettéosztva: a naptáresemények emlékeztetői a küszöb alatt,
/// az esti edzés-kérdések fölötte. Így az egyik csoport újraütemezése nem
/// törli a másikat — egy `cancelAll` mindig levinné mindkettőt.
const workoutIdBase = 1000000;

/// Az értesítés-gombok azonosítói. Egy helyen: az ütemezés és a feldolgozás
/// két külön fájlban van, string-literálként elcsúsznának.
const workoutDoneAction = 'workout_done';
const snoozeAction = 'snooze10';

/// Amit egy értesítés-válaszból csinálni kell.
enum NotificationAction { open, workoutDone, snooze }

/// Az [actionId] + [payload] párból eldönti a műveletet.
///
/// Ismeretlen vagy hiányzó azonosító = sima koppintás: csak navigálunk. Payload
/// nélkül a „+10 perc"-nek nem lenne mit újraütemeznie, az is nyitásra esik
/// vissza.
NotificationAction notificationActionFor(String? actionId, String? payload) =>
    switch (actionId) {
      workoutDoneAction => NotificationAction.workoutDone,
      snoozeAction when payload != null && payload.isNotEmpty =>
        NotificationAction.snooze,
      _ => NotificationAction.open,
    };

/// A `main()`-ből hívandó: időzóna-adatbázis, plugin, és az Android 13+
/// értesítési engedély.
///
/// [onTap] az értesítés payloadjában küldött útvonalat kapja. Hidegindításnál
/// a callback még nem élt, amikor a koppintás történt — ezért a plugin
/// indulási adatait külön is megnézzük.
///
/// [onWorkoutDone] a „Megvolt ✓", [onSnooze] a „+10 perc" gomb műveletét
/// végzi el — a hívó köti be, hogy ez a fájl ne függjön se a Riverpodtól, se a
/// naptártól.
///
/// ponytail: az akciók `showsUserInterface: true`-val futnak, tehát mindig a fő
/// isolate-ban, ahol él a router, a Riverpod és a prefs. Plafon: az app előjön
/// az akcióra. Háttérben futó gombhoz
/// `onDidReceiveBackgroundNotificationResponse` + `@pragma('vm:entry-point')`
/// kellene, saját prefs-olvasással és írási úttal, és a providereket akkor sem
/// tudná invalidálni.
Future<void> initNotifications({
  required void Function(String route) onTap,
  required void Function() onWorkoutDone,
  required void Function(int id, String payload) onSnooze,
}) async {
  tzdata.initializeTimeZones();
  await notifications.initialize(
    settings: const InitializationSettings(
      // Sziluett-ikon, nem a launcher ikon: a status bar egyszínűre maszkolja,
      // a színes adaptive iconból fehér paca lenne.
      // Puszta drawable-név, NEM '@drawable/...': a plugin getIdentifier-rel
      // oldja fel, az előtagra induláskor invalid_icon hibával elszáll.
      android: AndroidInitializationSettings('ic_notification'),
      iOS: DarwinInitializationSettings(),
    ),
    onDidReceiveNotificationResponse: (response) {
      final payload = response.payload;
      switch (notificationActionFor(response.actionId, payload)) {
        case NotificationAction.workoutDone:
          onWorkoutDone();
        case NotificationAction.snooze:
          if (response.id != null) onSnooze(response.id!, payload!);
        case NotificationAction.open:
          break;
      }
      // Az akció után is navigálunk: a „Megvolt" eredménye (pipa, sorozat) így
      // rögtön látszik, és ha a mai nap nem volt egyértelmű, ott lehet kézzel
      // pipálni.
      if (payload != null && payload.isNotEmpty) onTap(payload);
    },
  );
  await notifications
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.requestNotificationsPermission();

  final launch = await notifications.getNotificationAppLaunchDetails();
  final payload = launch?.notificationResponse?.payload;
  if ((launch?.didNotificationLaunchApp ?? false) &&
      payload != null &&
      payload.isNotEmpty) {
    onTap(payload);
  }
}
