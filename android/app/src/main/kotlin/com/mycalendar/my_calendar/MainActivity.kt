package com.mycalendar.my_calendar

import android.Manifest
import android.content.ActivityNotFoundException
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
                    "createEventWithGuests" -> handleCreateEventWithGuests(call, result)
                    "attendees" -> handleAttendees(call, result)
                    "inviteToEvent" -> handleInviteToEvent(call, result)
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
            TodayWidget.refresh(this)
            result.success(id)
        } catch (e: Exception) {
            result.error("INSERT_FAILED", e.message, null)
        }
    }

    /**
     * Meghívottas esemény: a naptáralkalmazás saját szerkesztőjét nyitjuk meg
     * előre kitöltve — NEM mi írjuk be az eseményt.
     *
     * Miért nem magunk? A meghívó kiküldése és a válaszok begyűjtése a Google
     * szinkron dolga. A `CalendarContract.Attendees` táblába közvetlenül beírt
     * vendég verziófüggően nem kap értesítést; a dokumentált út az
     * `ACTION_INSERT` + `EXTRA_EMAIL`, amit maga a Naptár küld tovább. Ezért
     * naptár-engedély sem kell hozzá: a beírást a Naptár végzi.
     *
     * A mentést a felhasználó ott nyomja meg, tehát nincs visszatérő
     * esemény-azonosító (a kategória-hozzárendelés így kimarad), és a célnaptárat
     * is a Naptár választja — jellemzően a fiók elsődleges naptára, ami itt épp a
     * kívánt cél. A lista magától frissül, amikor a felhasználó visszatér az
     * appba (lásd `AppLifecycleListener` az events_screen-ben).
     *
     * Az időargumentumok ugyanazok, mint a beszúrásnál (lásd `eventValues`):
     * egész naposnál UTC éjfél — a Naptár szerkesztője is így értelmezi.
     */
    private fun handleCreateEventWithGuests(call: MethodCall, result: MethodChannel.Result) {
        try {
            val intent = Intent(Intent.ACTION_INSERT)
                .setData(CalendarContract.Events.CONTENT_URI)
                .putExtra(CalendarContract.Events.TITLE, call.argument<String>("title"))
                .putExtra(Intent.EXTRA_EMAIL, call.argument<String>("guests"))
                .putExtra(
                    CalendarContract.EXTRA_EVENT_BEGIN_TIME,
                    call.argument<Number>("begin")!!.toLong(),
                )
                .putExtra(
                    CalendarContract.EXTRA_EVENT_END_TIME,
                    call.argument<Number>("end")!!.toLong(),
                )
                .putExtra(
                    CalendarContract.EXTRA_EVENT_ALL_DAY,
                    call.argument<Boolean>("allDay") == true,
                )
                // ponytail: nem dokumentált extra, csak jobb esetben veszi
                // figyelembe a Naptár. Ha nem, a felhasználó ugyanazon a
                // szerkesztőn belül egy kapcsolóval adja meg — a Dart oldal
                // ezért írja ki, hogy ezt ott érdemes ellenőrizni.
                .putExtra(CalendarContract.Events.GUESTS_CAN_MODIFY, true)
            call.argument<String>("rrule")?.let {
                intent.putExtra(CalendarContract.Events.RRULE, it)
            }
            startActivity(intent)
            result.success(null)
        } catch (e: ActivityNotFoundException) {
            result.error("NO_CALENDAR_APP", "Nincs naptáralkalmazás a készüléken.", null)
        } catch (e: Exception) {
            result.error("INSERT_FAILED", e.message, null)
        }
    }

    /**
     * Meglévő esemény megnyitása a naptáralkalmazás szerkesztőjében, hogy a
     * felhasználó meghívottat adhasson hozzá.
     *
     * Itt szándékosan nincs előre kitöltött vendéglista: az `EXTRA_EMAIL` csak az
     * `ACTION_INSERT`-nél dokumentált, `ACTION_EDIT`-nél a Naptár csendben
     * eldobhatná — a felhasználó pedig azt hinné, kiküldte a meghívót. A címeket
     * ezért ott írja be, és a meghívó kiküldését (plusz a vendég-jogosultságokat
     * és a „szóljunk a meghívottaknak?" kérdést) is az kezeli.
     *
     * A kezdés átadása az ismétlődő eseményekhez kell: ebből tudja a Naptár,
     * melyik előfordulást nyitja meg. A véget és az egész napos jelleget nem
     * küldjük — azokat a Naptár előtöltésnek vehetné, és egy hibás vég felülírná
     * a meglévő adatot.
     */
    private fun handleInviteToEvent(call: MethodCall, result: MethodChannel.Result) {
        try {
            val id = call.argument<String>("id")!!.toLong()
            startActivity(
                Intent(Intent.ACTION_EDIT)
                    .setData(ContentUris.withAppendedId(CalendarContract.Events.CONTENT_URI, id))
                    .putExtra(
                        CalendarContract.EXTRA_EVENT_BEGIN_TIME,
                        call.argument<Number>("begin")!!.toLong(),
                    ),
            )
            result.success(null)
        } catch (e: ActivityNotFoundException) {
            result.error("NO_CALENDAR_APP", "Nincs naptáralkalmazás a készüléken.", null)
        } catch (e: Exception) {
            result.error("EDIT_FAILED", e.message, null)
        }
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
