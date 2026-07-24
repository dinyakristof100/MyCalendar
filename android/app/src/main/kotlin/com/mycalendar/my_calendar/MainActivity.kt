package com.mycalendar.my_calendar

import android.Manifest
import android.content.ContentUris
import android.content.ContentValues
import android.content.pm.PackageManager
import android.os.Build
import android.provider.CalendarContract
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.TimeZone

/**
 * A közelgő naptáresemények kiolvasása az Android saját naptárából.
 *
 * Miért nem a Google Calendar API-ból? Mert az `calendar.events` OAuth
 * scope-ot igényelne, ami "érzékeny" — ettől jön a bejelentkezésnél a
 * "Google hasn't verified this app" képernyő, és eltüntetni csak saját
 * domainnel és hetekig tartó verifikációval lehetne. A naptár viszont
 * amúgy is szinkronizálva van a készüléken, egy sima futásidejű
 * engedéllyel olvasható.
 *
 * Csomag helyett közvetlen lekérdezés: a `device_calendar` 4.x a
 * `timezone` csomagon ütközik a flutter_local_notifications-szel, a 3.x
 * pedig már nem épül (AGP 3.4, jcenter, nincs namespace).
 */
class MainActivity : FlutterActivity() {

    private companion object {
        const val CHANNEL = "mycalendar/device_calendar"
        const val PERMISSION_REQUEST = 1001
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "upcomingEvents" -> handleUpcomingEvents(call.argument<Int>("days") ?: 14, result)
                    "eventsInRange" -> handleEventsInRange(call, result)
                    "createEvent" -> handleCreateEvent(call, result)
                    "versionCode" -> result.success(currentVersionCode())
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Kértünk-e már engedélyt ebben az élettartamban. Enélkül végtelen ciklus
     * lenne: a Dart oldal minden előtérbe kerüléskor újralekér, az elutasított
     * engedélykérés viszont pont egy előtérbe kerülés.
     */
    private var permissionAsked = false

    private fun handleUpcomingEvents(days: Int, result: MethodChannel.Result) {
        if (!ensureReadPermission(result)) return
        try {
            val begin = System.currentTimeMillis()
            result.success(queryRange(begin, begin + days * 24L * 60L * 60L * 1000L))
        } catch (e: Exception) {
            result.error("QUERY_FAILED", e.message, null)
        }
    }

    /** A naptár egy tetszőleges [begin, end) ablakának eseményei — a naptárnézet
     * hónapról hónapra ezt kéri. */
    private fun handleEventsInRange(call: MethodCall, result: MethodChannel.Result) {
        if (!ensureReadPermission(result)) return
        try {
            result.success(
                queryRange(
                    call.argument<Number>("begin")!!.toLong(),
                    call.argument<Number>("end")!!.toLong(),
                ),
            )
        } catch (e: Exception) {
            result.error("QUERY_FAILED", e.message, null)
        }
    }

    /**
     * Olvasási engedély megléte. Ha nincs, felkérjük (élettartamonként egyszer),
     * de nem várunk rá: a Dart oldal hibaként kapja, és a megadás utáni előtérbe
     * kerülés úgyis újralekér. Így nem kell a permission-callback köré aszinkron
     * állapotgépet építeni egyetlen lekérdezés miatt.
     */
    private fun ensureReadPermission(result: MethodChannel.Result): Boolean {
        if (has(Manifest.permission.READ_CALENDAR)) return true
        if (!permissionAsked) {
            permissionAsked = true
            requestCalendarPermissions()
        }
        result.error("PERMISSION_DENIED", "Nincs naptár-olvasási engedély.", null)
        return false
    }

    private fun handleCreateEvent(call: MethodCall, result: MethodChannel.Result) {
        if (!has(Manifest.permission.WRITE_CALENDAR)) {
            // Itt a felhasználó épp erre a műveletre vár, ezért a kérdés
            // minden próbálkozásnál mehet — nincs szükség a fenti ciklusvédő
            // jelzőre.
            requestCalendarPermissions()
            result.error("PERMISSION_DENIED", "Nincs naptár-írási engedély.", null)
            return
        }
        try {
            // A milliszekundum nem fér `Int`-be, a codec ezért `Long`-ként
            // hozza — de a `Number` biztosan illeszkedik mindkettőre.
            result.success(
                insertEvent(
                    call.argument<String>("title")!!,
                    call.argument<Number>("begin")!!.toLong(),
                    call.argument<Number>("end")!!.toLong(),
                ),
            )
        } catch (e: Exception) {
            result.error("INSERT_FAILED", e.message, null)
        }
    }

    /**
     * Beírás az elsődleges, írható naptárba.
     *
     * ponytail: nem kérdezzük meg, melyik naptárba menjen — a legtöbb
     * készüléken egy fiók van. Naptárválasztó akkor kell, ha valakinek több
     * írható naptára van, és számít a különbség.
     */
    private fun insertEvent(title: String, begin: Long, end: Long): String {
        val calendarId = writableCalendarId() ?: error("Nincs írható naptár a készüléken.")
        val values = ContentValues().apply {
            put(CalendarContract.Events.CALENDAR_ID, calendarId)
            put(CalendarContract.Events.TITLE, title)
            put(CalendarContract.Events.DTSTART, begin)
            put(CalendarContract.Events.DTEND, end)
            // Kötelező mező: enélkül a beszúrás kivételt dob.
            put(CalendarContract.Events.EVENT_TIMEZONE, TimeZone.getDefault().id)
        }
        val uri = contentResolver.insert(CalendarContract.Events.CONTENT_URI, values)
            ?: error("A naptár elutasította az eseményt.")
        return ContentUris.parseId(uri).toString()
    }

    /** A látható naptárak közül az, amibe a felhasználó írhat is. */
    private fun writableCalendarId(): Long? {
        val selection =
            "${CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL} >= " +
                "${CalendarContract.Calendars.CAL_ACCESS_CONTRIBUTOR} AND " +
                "${CalendarContract.Calendars.VISIBLE} = 1"
        contentResolver.query(
            CalendarContract.Calendars.CONTENT_URI,
            arrayOf(CalendarContract.Calendars._ID),
            selection,
            null,
            // Az elsődleges naptár előre — az az "enyém" a felhasználó fejében.
            "${CalendarContract.Calendars.IS_PRIMARY} DESC",
        )?.use { cursor ->
            if (cursor.moveToFirst()) return cursor.getLong(0)
        }
        return null
    }

    /** A telepített APK versionCode-ja — a Dart oldal ezt hasonlítja a GitHub
     * legfrissebb kiadásához, hogy van-e mit frissíteni. */
    private fun currentVersionCode(): Long {
        val info = packageManager.getPackageInfo(packageName, 0)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) info.longVersionCode
        else @Suppress("DEPRECATION") info.versionCode.toLong()
    }

    private fun has(permission: String): Boolean =
        ContextCompat.checkSelfPermission(this, permission) == PackageManager.PERMISSION_GRANTED

    /** Olvasás és írás egy kérdésben — a rendszer úgyis egy párbeszédet mutat. */
    private fun requestCalendarPermissions() = ActivityCompat.requestPermissions(
        this,
        arrayOf(Manifest.permission.READ_CALENDAR, Manifest.permission.WRITE_CALENDAR),
        PERMISSION_REQUEST,
    )

    /**
     * Az `Instances` tábla az ismétlődő eseményeket már előfordulásokra bontva
     * adja vissza a kért időablakra — pont, ami az emlékeztetőkhöz kell.
     *
     * Egész napos eseménynél a BEGIN érték **UTC éjfél**, nem helyi idő. A
     * Dart oldal ezt tudja, és nem vált időzónát rajta.
     */
    private fun queryRange(begin: Long, end: Long): List<Map<String, Any?>> {
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
        )

        val events = mutableListOf<Map<String, Any?>>()
        contentResolver.query(
            uri,
            projection,
            null,
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
                    ),
                )
            }
        }
        return events
    }
}
