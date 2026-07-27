package com.mycalendar.my_calendar

import android.Manifest
import android.content.ContentUris
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.CalendarContract
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
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
        const val PICK_FILE_REQUEST = 1002

        /** A megosztott mentések helye a gyorsítótárban — lásd `res/xml/file_paths.xml`. */
        const val EXPORT_DIR = "export"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "upcomingEvents" -> handleUpcomingEvents(call, result)
                    "eventsInRange" -> handleEventsInRange(call, result)
                    "calendars" -> handleCalendars(result)
                    "createEvent" -> handleCreateEvent(call, result)
                    "attendees" -> handleAttendees(call, result)
                    "addGuests" -> handleAddGuests(call, result)
                    "knownGuests" -> handleKnownGuests(result)
                    "syncCalendars" -> handleSyncCalendars(result)
                    "updateEvent" -> handleUpdateEvent(call, result)
                    "deleteEvent" -> handleDeleteEvent(call, result)
                    "pickTextFile" -> handlePickTextFile(result)
                    "shareTextFile" -> handleShareTextFile(call, result)
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

    private fun handleUpcomingEvents(call: MethodCall, result: MethodChannel.Result) {
        if (!ensureReadPermission(result)) return
        try {
            val days = call.argument<Int>("days") ?: 14
            val begin = System.currentTimeMillis()
            result.success(
                contentResolver.queryInstances(
                    begin,
                    begin + days * 24L * 60L * 60L * 1000L,
                    call.calendarIds(),
                ),
            )
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
                contentResolver.queryInstances(
                    call.argument<Number>("begin")!!.toLong(),
                    call.argument<Number>("end")!!.toLong(),
                    call.calendarIds(),
                ),
            )
        } catch (e: Exception) {
            result.error("QUERY_FAILED", e.message, null)
        }
    }

    /**
     * A naptárszűrő opcionális argumentuma. Hiányzó vagy üres lista = minden
     * naptár, vagyis a szűrő bevezetése előtti viselkedés. A milliszekundumokhoz
     * hasonlóan itt is `Number`-ként vesszük át: a codec kis id-t `Int`-ként hoz.
     */
    private fun MethodCall.calendarIds(): List<Long>? =
        argument<List<Number>>("calendarIds")?.map { it.toLong() }

    /** Az eszköz naptárai — ebből épül a beállítások naptárszűrője. */
    private fun handleCalendars(result: MethodChannel.Result) {
        if (!ensureReadPermission(result)) return
        try {
            result.success(contentResolver.queryCalendars())
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

    /**
     * Írási engedély megléte íráshoz (create/update/delete). Ha nincs, felkérjük
     * — itt a felhasználó épp erre a műveletre vár, ezért a kérdés minden
     * próbálkozásnál mehet, nem kell a `permissionAsked` ciklusvédő.
     */
    private fun ensureWritePermission(result: MethodChannel.Result): Boolean {
        if (has(Manifest.permission.WRITE_CALENDAR)) return true
        requestCalendarPermissions()
        result.error("PERMISSION_DENIED", "Nincs naptár-írási engedély.", null)
        return false
    }

    /**
     * A cím, az időpont, az egész napos jelleg és az ismétlődés mezői — a
     * beszúrás és a módosítás ugyanezt írja. Az egész napos jelleget mindkét
     * irányban ki kell írni: enélkül a szerkesztés elvenné egy meglévő egész
     * napos esemény ALL_DAY jelzőjét.
     *
     * Egész naposnál a Dart oldal a nap UTC éjfelét küldi kezdésnek és a
     * következő nap UTC éjfelét végnek (az Android félig nyílt intervallumot
     * vár), az időzóna pedig kötelezően UTC — helyi zónával a naptár átcsúsztatná
     * a szomszédos napra.
     *
     * Ismétlődőnél a naptár DTEND helyett DURATION-t vár (és a kettő együtt
     * érvénytelen adat): a hosszt a kapott intervallumból számoljuk, egész
     * naposra a napalapú `P1D` kell. A DTEND-et kifejezetten nullázzuk, mert a
     * módosítást a provider a sor meglévő mezőivel együtt ellenőrzi.
     *
     * A leírás és a hely csak akkor íródik, ha a hívó küldte — az importált
     * mentésnél van mit beletenni. A szerkesztés nem küldi őket, így egy meglévő
     * esemény leírását nem törli le.
     */
    private fun eventValues(call: MethodCall): ContentValues {
        val allDay = call.argument<Boolean>("allDay") == true
        // A milliszekundum nem fér `Int`-be, a codec ezért `Long`-ként hozza —
        // de a `Number` biztosan illeszkedik mindkettőre.
        val begin = call.argument<Number>("begin")!!.toLong()
        val end = call.argument<Number>("end")!!.toLong()
        val rrule = call.argument<String>("rrule")
        return ContentValues().apply {
            put(CalendarContract.Events.TITLE, call.argument<String>("title")!!)
            put(CalendarContract.Events.DTSTART, begin)
            if (rrule == null) {
                put(CalendarContract.Events.DTEND, end)
            } else {
                putNull(CalendarContract.Events.DTEND)
                put(CalendarContract.Events.RRULE, rrule)
                put(
                    CalendarContract.Events.DURATION,
                    if (allDay) "P1D" else "PT${(end - begin) / 1000}S",
                )
            }
            put(CalendarContract.Events.ALL_DAY, if (allDay) 1 else 0)
            call.argument<String>("description")?.let {
                put(CalendarContract.Events.DESCRIPTION, it)
            }
            call.argument<String>("location")?.let {
                put(CalendarContract.Events.EVENT_LOCATION, it)
            }
            // Kötelező mező: enélkül a beszúrás kivételt dob.
            put(
                CalendarContract.Events.EVENT_TIMEZONE,
                if (allDay) "UTC" else TimeZone.getDefault().id,
            )
        }
    }

    private fun handleCreateEvent(call: MethodCall, result: MethodChannel.Result) {
        if (!ensureWritePermission(result)) return
        try {
            val id = insertEvent(
                eventValues(call),
                call.argument<Number>("calendarId")?.toLong(),
            )
            insertGuests(id.toLong(), call.guests())
            TodayWidget.refresh(this)
            result.success(id)
        } catch (e: Exception) {
            result.error("INSERT_FAILED", e.message, null)
        }
    }

    /** Meghívottak hozzáadása meglévő eseményhez — lásd [insertGuests]. */
    private fun handleAddGuests(call: MethodCall, result: MethodChannel.Result) {
        if (!ensureWritePermission(result)) return
        try {
            insertGuests(call.argument<String>("id")!!.toLong(), call.guests())
            result.success(null)
        } catch (e: Exception) {
            result.error("INSERT_FAILED", e.message, null)
        }
    }

    /** A meghívottak e-mail címei. Hiányzó kulcs = nincs meghívott. */
    private fun MethodCall.guests(): List<String> =
        argument<List<String>>("guests") ?: emptyList()

    /**
     * A meghívottak beírása az esemény mellé — közvetlenül a naptár
     * `Attendees` táblájába, naptáralkalmazás megnyitása nélkül.
     *
     * A meghívó kiküldése innentől a Google szinkron dolga: az `Attendees`
     * táblába írástól a provider „szennyezettnek" jelöli az esemény sorát, a
     * szinkron feltölti, a Google szervere pedig kiküldi a meghívót és begyűjti a
     * válaszokat (azok a [queryAttendees]-ben jelennek meg). Hálózatot itt nem
     * használunk, és nem is várunk rá: a következő szinkronig a meghívott „még
     * nem válaszolt" állapotban áll.
     *
     * A `GUESTS_CAN_MODIFY` azért kell, hogy a meghívottak is szerkeszthessék az
     * eseményt — enélkül csak a szervező módosíthatná, és a változás nem lenne
     * kétirányú.
     *
     * ponytail: a két esemény-jelző írása hibát elnyelve fut. Ha egy gyártói
     * providernél nem írható valamelyik, a meghívottak akkor is bekerülnek — az a
     * lényeg —, a jelzőket pedig a szinkron a szerver adataival amúgy is
     * felülírja.
     */
    private fun insertGuests(eventId: Long, guests: List<String>) {
        // Aki már meg van hívva, azt nem hívjuk meg másodszor: az „ugyanaz a cím
        // kétszer" a listában is két sorként jelenne meg.
        val existing = contentResolver.queryAttendees(eventId)
            .mapNotNull { (it["email"] as String?)?.lowercase() }
            .toSet()
        val invited = guests.filter { it.lowercase() !in existing }
        if (invited.isEmpty()) return

        try {
            contentResolver.update(
                ContentUris.withAppendedId(CalendarContract.Events.CONTENT_URI, eventId),
                ContentValues().apply {
                    // Enélkül a naptár és a szinkron „meghívottak nélküli"
                    // eseménynek látja, és eldobhatja a sorokat.
                    put(CalendarContract.Events.HAS_ATTENDEE_DATA, 1)
                    put(CalendarContract.Events.GUESTS_CAN_MODIFY, 1)
                },
                null,
                null,
            )
        } catch (e: Exception) {
            // Szándékosan elnyelve: a meghívottak beírása lentebb így is lefut.
        }

        contentResolver.bulkInsert(
            CalendarContract.Attendees.CONTENT_URI,
            invited.map { email ->
                ContentValues().apply {
                    put(CalendarContract.Attendees.EVENT_ID, eventId)
                    put(CalendarContract.Attendees.ATTENDEE_EMAIL, email)
                    put(
                        CalendarContract.Attendees.ATTENDEE_RELATIONSHIP,
                        CalendarContract.Attendees.RELATIONSHIP_ATTENDEE,
                    )
                    put(
                        CalendarContract.Attendees.ATTENDEE_TYPE,
                        CalendarContract.Attendees.TYPE_REQUIRED,
                    )
                    // „Meghívtuk, még nem válaszolt" — a választ a szinkron hozza.
                    put(
                        CalendarContract.Attendees.ATTENDEE_STATUS,
                        CalendarContract.Attendees.ATTENDEE_STATUS_INVITED,
                    )
                }
            }.toTypedArray(),
        )
    }

    /**
     * A már ismert meghívottak címei — ebből ajánl a meghívottak mezője.
     *
     * Engedély nélkül üres lista, nem hiba: a javaslat kényelmi funkció, nem
     * érdemes érte hibát mutatni a felhasználónak. (Az `ensureReadPermission`
     * ilyenkor amúgy is felkéri az engedélyt.)
     */
    private fun handleKnownGuests(result: MethodChannel.Result) {
        if (!has(Manifest.permission.READ_CALENDAR)) {
            result.success(emptyList<String>())
            return
        }
        try {
            result.success(contentResolver.queryKnownGuests())
        } catch (e: Exception) {
            result.error("QUERY_FAILED", e.message, null)
        }
    }

    /**
     * Friss szinkron kérése a naptárfiókoktól (lásd [requestCalendarSync]) — a
     * lehúzós frissítés és a meghívottak lapja ezzel kezdi.
     *
     * Sosem ad hibát: a szinkron kérése kényelmi lépés, engedély vagy hálózat
     * híján egyszerűen nem történik semmi, és a hívó a helyi adatot mutatja
     * tovább. Engedélyt sem kérünk érte — az olvasáskor amúgy is előjön.
     */
    private fun handleSyncCalendars(result: MethodChannel.Result) {
        if (has(Manifest.permission.READ_CALENDAR)) {
            try {
                contentResolver.requestCalendarSync()
            } catch (e: Exception) {
                // Szándékosan elnyelve — lásd a fenti magyarázatot.
            }
        }
        result.success(null)
    }

    /** Egy esemény meghívottai és a válaszuk — a részletek lapja mutatja. */
    private fun handleAttendees(call: MethodCall, result: MethodChannel.Result) {
        if (!ensureReadPermission(result)) return
        try {
            result.success(
                contentResolver.queryAttendees(call.argument<String>("id")!!.toLong()),
            )
        } catch (e: Exception) {
            result.error("QUERY_FAILED", e.message, null)
        }
    }

    /**
     * Meglévő esemény címének, időpontjának és egész napos jellegének
     * módosítása. Csak ezeket írja, a többit (leírás, hely) érintetlenül hagyja.
     *
     * ponytail: az `id` az esemény sora, nem egy ismétlődés-előfordulásé, ezért
     * ismétlődő eseménynél a módosítás az egész sorozatra hat — a Dart oldal
     * ezért figyelmezteti a felhasználót. Az „csak ez az előfordulás" ág helye:
     * EXDATE hozzáfűzése a sorhoz (az előfordulás kezdetével), plusz egy új,
     * önálló esemény a módosított adatokkal.
     */
    private fun handleUpdateEvent(call: MethodCall, result: MethodChannel.Result) {
        if (!ensureWritePermission(result)) return
        try {
            val id = call.argument<String>("id")!!.toLong()
            val values = eventValues(call)
            val uri = ContentUris.withAppendedId(CalendarContract.Events.CONTENT_URI, id)
            if (contentResolver.update(uri, values, null, null) == 0) {
                error("A naptár nem találta a módosítandó eseményt.")
            }
            TodayWidget.refresh(this)
            result.success(null)
        } catch (e: Exception) {
            result.error("UPDATE_FAILED", e.message, null)
        }
    }

    /**
     * ponytail: a sor törlése az egész sorozatot viszi. Egy előfordulás
     * törléséhez EXDATE-et kellene fűzni a sor meglévő EXDATE-jéhez — a Dart
     * oldal addig csak az „összes"-t ajánlja fel, figyelmeztetéssel.
     */
    private fun handleDeleteEvent(call: MethodCall, result: MethodChannel.Result) {
        if (!ensureWritePermission(result)) return
        try {
            val id = call.argument<String>("id")!!.toLong()
            val uri = ContentUris.withAppendedId(CalendarContract.Events.CONTENT_URI, id)
            if (contentResolver.delete(uri, null, null) == 0) {
                error("A naptár nem találta a törlendő eseményt.")
            }
            TodayWidget.refresh(this)
            result.success(null)
        } catch (e: Exception) {
            result.error("DELETE_FAILED", e.message, null)
        }
    }

    /**
     * Beírás a [calendarId] naptárba — ezt a Dart oldal a bejelentkezett fiók
     * saját naptárára állítja.
     *
     * Enélkül (id nélküli hívás) a készülék első írható naptára jön, ami több
     * fióknál könnyen egy MÁSIK e-mail címé: az esemény létrejön, de a
     * bejelentkezett fiók naptárában sehol — pont ez volt a hiba.
     */
    private fun insertEvent(values: ContentValues, calendarId: Long?): String {
        val target = calendarId
            ?: writableCalendarId()
            ?: error("Nincs írható naptár a készüléken.")
        values.put(CalendarContract.Events.CALENDAR_ID, target)
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

    /**
     * A folyamatban lévő fájlválasztás Dart-oldali válasza. A rendszer
     * választóablaka külön activity, az eredménye [onActivityResult]-ban jön —
     * addig itt vár a `result`.
     */
    private var pendingPick: MethodChannel.Result? = null

    /**
     * A rendszer fájlválasztójának megnyitása, és a választott fájl tartalmának
     * visszaadása szövegként. Elvetéskor `null`.
     *
     * A típusszűrő szándékosan `* / *`: a `.csv`-t sok fájlkezelő és letöltés
     * `application/octet-stream`-ként tartja nyilván, a szűkebb `text/csv`
     * ezeknél elrejtené a keresett fájlt. Nem kér tárhely-engedélyt: az
     * `ACTION_OPEN_DOCUMENT` a rendszer választóján át ad hozzáférést.
     */
    private fun handlePickTextFile(result: MethodChannel.Result) {
        if (pendingPick != null) {
            result.error("PICK_BUSY", "Már fut egy fájlválasztás.", null)
            return
        }
        try {
            pendingPick = result
            startActivityForResult(
                Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "*/*"
                },
                PICK_FILE_REQUEST,
            )
        } catch (e: Exception) {
            pendingPick = null
            result.error("PICK_FAILED", e.message, null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != PICK_FILE_REQUEST) return
        // A `pendingPick` kinullázása AZONNAL: bármelyik ág fut le, a következő
        // választás indulhasson.
        val result = pendingPick ?: return
        pendingPick = null
        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null) {
            result.success(null) // mégsem
            return
        }
        try {
            val text = contentResolver.openInputStream(uri)
                ?.bufferedReader()
                ?.use { it.readText() }
                ?: error("A fájl nem olvasható.")
            result.success(text)
        } catch (e: Exception) {
            result.error("READ_FAILED", e.message, null)
        }
    }

    /**
     * A kapott szöveg fájlba írása és kiajánlása a rendszer megosztó-ablakának
     * (e-mail, üzenet, Bluetooth, felhő — ami a telefonon van).
     *
     * A fájl a gyorsítótárba kerül, és `FileProvider`-en át kap ideiglenes
     * olvasási jogot: `file://` URI-t az Android N óta nem fogad el más app.
     * Takarítani nem kell, a gyorsítótárat a rendszer üríti.
     */
    private fun handleShareTextFile(call: MethodCall, result: MethodChannel.Result) {
        try {
            val name = call.argument<String>("name")!!
            val file = File(File(cacheDir, EXPORT_DIR).apply { mkdirs() }, name)
            file.writeText(call.argument<String>("content")!!)
            val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
            startActivity(
                Intent.createChooser(
                    Intent(Intent.ACTION_SEND).apply {
                        type = "text/csv"
                        putExtra(Intent.EXTRA_STREAM, uri)
                        putExtra(Intent.EXTRA_SUBJECT, name)
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    },
                    "Naptármentés küldése",
                ),
            )
            result.success(null)
        } catch (e: Exception) {
            result.error("SHARE_FAILED", e.message, null)
        }
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
}
