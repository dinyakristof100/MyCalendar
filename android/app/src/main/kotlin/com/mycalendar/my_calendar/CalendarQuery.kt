package com.mycalendar.my_calendar

import android.accounts.Account
import android.content.ContentResolver
import android.content.ContentUris
import android.os.Bundle
import android.provider.CalendarContract

/**
 * Az eszköz naptárának olvasása — külön fájlban, mert KÉT helyről kell:
 * a Flutter-csatornából (`MainActivity`) és a kezdőképernyő-widgetből
 * (`TodayWidget`). A widget frissülésekor a Dart oldal nem is fut, tehát nem
 * kérheti az adatot az appon keresztül.
 *
 * A visszaadott `Map` ugyanaz a forma, amit a MethodChannel átvisz a Dart
 * oldalra — a widget is ebből olvas. ponytail: nincs külön adatosztály a két
 * fogyasztó kedvéért; ha valaha három lesz belőlük, akkor jöhet.
 */

/**
 * Az eszközön lévő naptárak: id, megjelenő név, fiók és szín.
 *
 * A szín (`CALENDAR_COLOR`) lehet null — a hívó dolga alapértelmezést tenni
 * helyette.
 */
fun ContentResolver.queryCalendars(): List<Map<String, Any?>> {
    val projection = arrayOf(
        CalendarContract.Calendars._ID,
        CalendarContract.Calendars.CALENDAR_DISPLAY_NAME,
        CalendarContract.Calendars.ACCOUNT_NAME,
        CalendarContract.Calendars.CALENDAR_COLOR,
    )
    val calendars = mutableListOf<Map<String, Any?>>()
    query(
        CalendarContract.Calendars.CONTENT_URI,
        projection,
        null,
        null,
        // Fiókonként csoportosítva, azon belül név szerint — ebben a sorrendben
        // keresi a felhasználó is a listában.
        "${CalendarContract.Calendars.ACCOUNT_NAME} ASC, " +
            "${CalendarContract.Calendars.CALENDAR_DISPLAY_NAME} ASC",
    )?.use { cursor ->
        while (cursor.moveToNext()) {
            calendars.add(
                mapOf(
                    "id" to cursor.getLong(0),
                    "name" to cursor.getString(1),
                    "account" to cursor.getString(2),
                    "color" to if (cursor.isNull(3)) null else cursor.getInt(3),
                ),
            )
        }
    }
    return calendars
}

/**
 * Egy esemény meghívottai: kit hívtak meg, és mit válaszolt.
 *
 * A válasz szövegként megy át (nem `ATTENDEE_STATUS` számként) — így a Dart
 * oldalon nem kell a provider számkódjait duplikálni.
 *
 * Csak olvasási engedély kell hozzá, hálózat nem: a meghívottak válaszát a
 * Google szinkron tartja frissen ebben a táblában.
 */
fun ContentResolver.queryAttendees(eventId: Long): List<Map<String, Any?>> {
    val projection = arrayOf(
        CalendarContract.Attendees.ATTENDEE_NAME,
        CalendarContract.Attendees.ATTENDEE_EMAIL,
        CalendarContract.Attendees.ATTENDEE_STATUS,
        CalendarContract.Attendees.ATTENDEE_RELATIONSHIP,
    )
    val guests = mutableListOf<Map<String, Any?>>()
    query(
        CalendarContract.Attendees.CONTENT_URI,
        projection,
        "${CalendarContract.Attendees.EVENT_ID} = ?",
        arrayOf(eventId.toString()),
        null,
    )?.use { cursor ->
        while (cursor.moveToNext()) {
            guests.add(
                mapOf(
                    "name" to cursor.getString(0),
                    "email" to cursor.getString(1),
                    "status" to attendeeStatus(cursor.getInt(2)),
                    "organizer" to (
                        cursor.getInt(3) ==
                            CalendarContract.Attendees.RELATIONSHIP_ORGANIZER
                        ),
                ),
            )
        }
    }
    return guests
}

/**
 * A megadott eseményekhez az ELFOGADOTT résztvevők, eseményenként: a nevük,
 * vagy ha a naptár nem tud nevet, az e-mail címük.
 *
 * Az [owners] az esemény azonosítóját a saját naptárfiókjához köti
 * (`OWNER_ACCOUNT`). Ez jellemzően maga a felhasználó — őt kihagyjuk a
 * listából: a kártyán az a kérdés, ki MÁS lesz még ott.
 *
 * Egyetlen lekérdezés az egész ablakra. Eseményenként külön kérdezni (mint a
 * részletek lapja teszi) itt tucatnyi felesleges olvasás lenne — a lista minden
 * frissüléskor újraépül.
 */
private fun ContentResolver.queryAcceptedGuests(
    owners: Map<Long, String?>,
): Map<Long, List<String>> {
    if (owners.isEmpty()) return emptyMap()
    val guests = mutableMapOf<Long, MutableList<String>>()
    query(
        CalendarContract.Attendees.CONTENT_URI,
        arrayOf(
            CalendarContract.Attendees.EVENT_ID,
            CalendarContract.Attendees.ATTENDEE_NAME,
            CalendarContract.Attendees.ATTENDEE_EMAIL,
        ),
        // Az id-k a saját kurzorunkból jönnek `Long`-ként, tehát a listából
        // épített `IN (…)` nem lehet befecskendezés.
        "${CalendarContract.Attendees.EVENT_ID} IN (${owners.keys.joinToString(",")}) AND " +
            "${CalendarContract.Attendees.ATTENDEE_STATUS} = ?",
        arrayOf(CalendarContract.Attendees.ATTENDEE_STATUS_ACCEPTED.toString()),
        null,
    )?.use { cursor ->
        while (cursor.moveToNext()) {
            val eventId = cursor.getLong(0)
            val email = cursor.getString(2)
            if (email != null && email.equals(owners[eventId], ignoreCase = true)) continue
            val label = cursor.getString(1)?.trim()?.ifEmpty { null } ?: email ?: continue
            guests.getOrPut(eventId) { mutableListOf() }.add(label)
        }
    }
    return guests
}

/**
 * Az eddig ismert meghívottak e-mail címei: minden cím, ami a naptár
 * meghívott-táblájában szerepel — akit valaha meghívtunk, és aki minket hívott
 * meg, plusz a közös események többi résztvevője.
 *
 * Nem kell hozzá névjegy-engedély (READ_CONTACTS): ez ugyanaz a naptár-olvasás,
 * amit az app amúgy is használ.
 *
 * Gyakoriság szerint csökkenő, azon belül betűrendben — akivel a legtöbbször
 * volt közös eseményünk, az kerül előre a javaslatok között.
 */
fun ContentResolver.queryKnownGuests(): List<String> {
    val counts = mutableMapOf<String, Int>()
    query(
        CalendarContract.Attendees.CONTENT_URI,
        arrayOf(CalendarContract.Attendees.ATTENDEE_EMAIL),
        null,
        null,
        null,
    )?.use { cursor ->
        while (cursor.moveToNext()) {
            val email = cursor.getString(0)?.trim()?.lowercase()
            if (email.isNullOrEmpty() || !email.contains("@")) continue
            counts[email] = (counts[email] ?: 0) + 1
        }
    }
    return counts.entries
        .sortedWith(compareByDescending<Map.Entry<String, Int>> { it.value }.thenBy { it.key })
        .map { it.key }
}

/**
 * Friss szinkron kérése a naptárfiókoktól.
 *
 * A naptártábla a készüléken csak TÜKÖR: a meghívottak válaszát a Google
 * szinkronja írja bele. Az app eddig sosem kért szinkront, csak olvasta a
 * tükröt — a háttérszinkron viszont órákat is késhet (Doze, gyártói
 * energiakezelés). Így maradhatott a lapon „még nem válaszolt" olyan
 * meghívottnál, aki a Google szerverén rég elfogadta a meghívót.
 *
 * `SYNC_EXTRAS_MANUAL` + `SYNC_EXTRAS_EXPEDITED`: a felhasználó ott áll a
 * képernyő előtt és most várja az adatot — az ilyen kérést az Android soron
 * kívül futtatja, nem halogatja a szokásos ütemezéssel.
 *
 * Fiókonként (nem naptáranként) egy kérés: egy fiókhoz több naptár is tartozik
 * (ünnepnapok, órarend), a szinkron viszont a fiók egészére fut.
 *
 * Nem várunk a végére: a szinkron a saját szálán dolgozik, az eredménye a
 * naptártáblába kerül — a hívó dolga újra lekérdezni (lásd a Dart oldali
 * `eventGuestsProvider`-t).
 */
fun ContentResolver.requestCalendarSync() {
    val extras = Bundle().apply {
        putBoolean(ContentResolver.SYNC_EXTRAS_MANUAL, true)
        putBoolean(ContentResolver.SYNC_EXTRAS_EXPEDITED, true)
    }
    val accounts = mutableSetOf<Pair<String, String>>()
    query(
        CalendarContract.Calendars.CONTENT_URI,
        arrayOf(
            CalendarContract.Calendars.ACCOUNT_NAME,
            CalendarContract.Calendars.ACCOUNT_TYPE,
        ),
        // A fiók nélküli, helyi naptárnak nincs mit szinkronizálnia.
        "${CalendarContract.Calendars.ACCOUNT_TYPE} != ?",
        arrayOf(CalendarContract.ACCOUNT_TYPE_LOCAL),
        null,
    )?.use { cursor ->
        while (cursor.moveToNext()) {
            val name = cursor.getString(0) ?: continue
            val type = cursor.getString(1) ?: continue
            accounts.add(name to type)
        }
    }
    for ((name, type) in accounts) {
        ContentResolver.requestSync(Account(name, type), CalendarContract.AUTHORITY, extras)
    }
}

/** A meghívott válasza szövegesen. Ami nem ismerhető fel, az „nem válaszolt". */
private fun attendeeStatus(status: Int): String = when (status) {
    CalendarContract.Attendees.ATTENDEE_STATUS_ACCEPTED -> "accepted"
    CalendarContract.Attendees.ATTENDEE_STATUS_DECLINED -> "declined"
    CalendarContract.Attendees.ATTENDEE_STATUS_TENTATIVE -> "tentative"
    else -> "pending"
}

/**
 * Az `Instances` tábla a [begin, end) ablakra. Ez a tábla az ismétlődő
 * eseményeket már előfordulásokra bontva adja vissza — pont, ami az
 * emlékeztetőkhöz és a naptárnézethez kell.
 *
 * [calendarIds] üres vagy null: minden naptár (ez az alapértelmezés). Egyébként
 * csak a felsoroltak. Az id-k a saját [queryCalendars] lekérdezésünkből jönnek
 * `Long`-ként, tehát a listából épített `IN (…)` nem lehet befecskendezés.
 *
 * Egész napos eseménynél a BEGIN érték **UTC éjfél**, nem helyi idő. A hívóknak
 * (Dart oldal és widget) ezt tudniuk kell: tilos időzónát váltva értelmezni.
 */
fun ContentResolver.queryInstances(
    begin: Long,
    end: Long,
    calendarIds: List<Long>? = null,
): List<Map<String, Any?>> {
    val uri = CalendarContract.Instances.CONTENT_URI.buildUpon().let {
        ContentUris.appendId(it, begin)
        ContentUris.appendId(it, end)
        it.build()
    }
    val projection = arrayOf(
        CalendarContract.Instances.EVENT_ID,
        CalendarContract.Instances.TITLE,
        CalendarContract.Instances.BEGIN,
        CalendarContract.Instances.ALL_DAY,
        CalendarContract.Instances.END,
        CalendarContract.Instances.DESCRIPTION,
        CalendarContract.Instances.EVENT_LOCATION,
        // Ebből tudja a UI, hogy a szerkesztés/törlés egy egész sorozatra hat.
        CalendarContract.Instances.RRULE,
        // Az esemény naptárának fiókja — ehhez képest „másik" résztvevő a többi
        // meghívott (lásd [queryAcceptedGuests]).
        CalendarContract.Instances.OWNER_ACCOUNT,
    )
    val selection = if (calendarIds.isNullOrEmpty()) {
        null
    } else {
        "${CalendarContract.Instances.CALENDAR_ID} IN (${calendarIds.joinToString(",")})"
    }

    val events = mutableListOf<MutableMap<String, Any?>>()
    // Eseményenként a naptár fiókja. Ismétlődőnél minden előfordulás ugyanaz az
    // esemény, tehát a map magától összevonja őket.
    val owners = mutableMapOf<Long, String?>()
    query(
        uri,
        projection,
        selection,
        null,
        "${CalendarContract.Instances.BEGIN} ASC",
    )?.use { cursor ->
        while (cursor.moveToNext()) {
            val eventId = cursor.getLong(0)
            owners[eventId] = cursor.getString(8)
            events.add(
                mutableMapOf(
                    "id" to eventId.toString(),
                    "title" to cursor.getString(1),
                    "begin" to cursor.getLong(2),
                    "allDay" to (cursor.getInt(3) == 1),
                    "end" to cursor.getLong(4),
                    "description" to cursor.getString(5),
                    "location" to cursor.getString(6),
                    "rrule" to cursor.getString(7),
                    // Az elfogadott résztvevők egy lekérdezésből, alább.
                    "guests" to emptyList<String>(),
                ),
            )
        }
    }

    val guests = queryAcceptedGuests(owners)
    if (guests.isNotEmpty()) {
        for (event in events) {
            event["guests"] = guests[(event["id"] as String).toLong()] ?: continue
        }
    }
    return events
}
