package com.mycalendar.my_calendar

import android.content.ContentResolver
import android.content.ContentUris
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
    )
    val selection = if (calendarIds.isNullOrEmpty()) {
        null
    } else {
        "${CalendarContract.Instances.CALENDAR_ID} IN (${calendarIds.joinToString(",")})"
    }

    val events = mutableListOf<Map<String, Any?>>()
    query(
        uri,
        projection,
        selection,
        null,
        "${CalendarContract.Instances.BEGIN} ASC",
    )?.use { cursor ->
        while (cursor.moveToNext()) {
            events.add(
                mapOf(
                    "id" to cursor.getLong(0).toString(),
                    "title" to cursor.getString(1),
                    "begin" to cursor.getLong(2),
                    "allDay" to (cursor.getInt(3) == 1),
                    "end" to cursor.getLong(4),
                    "description" to cursor.getString(5),
                    "location" to cursor.getString(6),
                    "rrule" to cursor.getString(7),
                ),
            )
        }
    }
    return events
}
