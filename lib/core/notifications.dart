import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;

/// Az app egyetlen értesítés-plugin példánya.
final notifications = FlutterLocalNotificationsPlugin();

/// Az azonosítótér kettéosztva: a naptáresemények emlékeztetői a küszöb alatt,
/// az esti edzés-kérdések fölötte. Így az egyik csoport újraütemezése nem
/// törli a másikat — egy `cancelAll` mindig levinné mindkettőt.
const workoutIdBase = 1000000;

/// A `main()`-ből hívandó: időzóna-adatbázis, plugin, és az Android 13+
/// értesítési engedély.
///
/// [onTap] az értesítés payloadjában küldött útvonalat kapja. Hidegindításnál
/// a callback még nem élt, amikor a koppintás történt — ezért a plugin
/// indulási adatait külön is megnézzük.
Future<void> initNotifications({
  required void Function(String route) onTap,
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
      final route = response.payload;
      if (route != null && route.isNotEmpty) onTap(route);
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
