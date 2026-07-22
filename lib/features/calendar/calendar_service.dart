import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/calendar/v3.dart';

/// Csak eseményekhez kell hozzáférés, a teljes naptárhoz (naptárak létrehozása,
/// ACL-ek) nem. Ez a scope van felvéve a Google Cloud consent screenre is.
const _scopes = [CalendarApi.calendarEventsScope];

/// Az esemény kezdete, egész napos jelzéssel.
///
/// A Calendar API egész napos eseménynél a `date` mezőt tölti (helyi éjfélre
/// parse-olva), időpontosnál a `dateTime`-ot (RFC3339, jellemzően UTC). A
/// `date`-et TILOS időzóna-váltani, mert átcsúszna a szomszédos napra —
/// ezért jön külön az `allDay` jelzés a megjelenítéshez.
({DateTime at, bool allDay})? eventStart(Event event) {
  final when = event.start;
  final dateTime = when?.dateTime;
  if (dateTime != null) return (at: dateTime.toLocal(), allDay: false);
  final date = when?.date;
  if (date != null) return (at: date, allDay: true);
  return null;
}

/// `07. 23.` egész naposra, `07. 23. 14:30` időpontosra.
///
/// ponytail: kézi formázás, mert az app-ban nincs `intl` és nincsenek magyar
/// locale delegate-ek — ha kell a „hétfő”/„holnap” jellegű szöveg, akkor jöhet.
String formatStart(({DateTime at, bool allDay}) start) {
  String pad(int n) => n.toString().padLeft(2, '0');
  final date = '${pad(start.at.month)}. ${pad(start.at.day)}.';
  if (start.allDay) return '$date egész nap';
  return '$date ${pad(start.at.hour)}:${pad(start.at.minute)}';
}

/// A következő 14 nap eseményei a felhasználó fő naptárából, kezdés szerint.
final upcomingEventsProvider = FutureProvider<List<Event>>((ref) async {
  final authz = GoogleSignIn.instance.authorizationClient;
  // A scope NEM jön a bejelentkezéssel (google_sign_in 7.x): ha még nincs
  // megadva, itt kérünk rá — a provider a foregroundban lévő UI-ból fut, tehát
  // a felhasználói interakciót igénylő ág is megengedett.
  final granted = await authz.authorizationForScopes(_scopes) ??
      await authz.authorizeScopes(_scopes);

  final client = granted.authClient(scopes: _scopes);
  try {
    final now = DateTime.now();
    final events = await CalendarApi(client).events.list(
          'primary',
          timeMin: now.toUtc(),
          timeMax: now.add(const Duration(days: 14)).toUtc(),
          // Az ismétlődő eseményeket példányokra bontja. Enélkül nincs
          // startTime szerinti rendezés, és emlékeztetőt sem lehetne az egyes
          // előfordulásokhoz időzíteni.
          singleEvents: true,
          orderBy: 'startTime',
        );
    // ponytail: nincs lapozás, 14 nap belefér az alap 250-es limitbe.
    return events.items ?? const [];
  } finally {
    client.close();
  }
});
