package com.mycalendar.my_calendar

import android.Manifest
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.text.format.DateFormat
import android.view.View
import android.widget.RemoteViews
import androidx.core.content.ContextCompat
import java.util.Calendar
import java.util.Date

/**
 * Kezdőképernyő-widget: a mai nap legfeljebb három eseménye.
 *
 * Miért nem a Flutter oldalról jön az adat? Mert a widget frissülésekor a Dart
 * kód nem fut — a rendszer csak ezt a receivert ébreszti. Ezért olvassuk
 * közvetlenül a naptárat ([queryInstances], ugyanaz a lekérdezés, amit a
 * MethodChannel is használ).
 *
 * Miért RemoteViews és nem Glance? Mert a projektben nincs Compose beállítva, és
 * három sornyi szöveghez nem éri meg behozni.
 *
 * ponytail: a widget MINDEN naptárat mutat — a beállításokban kikapcsoltakat
 * is. A kiválasztás a Flutter SharedPreferences-ében él, amit innen csak a
 * `FlutterSharedPreferences` XML kulcsainak ismeretében lehetne kiolvasni. Ha
 * zavaróvá válik: a `flutter.visibleCalendars` JSON-t kell beolvasni és a
 * [queryCalendars] fiók+név párosával összevetni.
 */
class TodayWidget : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        val views = buildViews(context)
        for (id in appWidgetIds) appWidgetManager.updateAppWidget(id, views)
    }

    companion object {
        /** Ennyi esemény fér ki, a többi a „+N további" sorba megy. */
        private const val MAX_ROWS = 3

        private val ROWS = intArrayOf(R.id.widget_row_1, R.id.widget_row_2, R.id.widget_row_3)
        private val TIMES = intArrayOf(R.id.widget_time_1, R.id.widget_time_2, R.id.widget_time_3)
        private val TITLES = intArrayOf(R.id.widget_event_1, R.id.widget_event_2, R.id.widget_event_3)

        /**
         * A kirakott widgetek azonnali frissítése. Az app hívja, miután eseményt
         * írt — a fél órás rendszerciklusra várni túl lassú lenne ahhoz, hogy az
         * imént felvett esemény megjelenjen.
         *
         * Nincs kirakott widget: nincs mit tenni, a lekérdezés is elmarad.
         */
        fun refresh(context: Context) {
            val manager = AppWidgetManager.getInstance(context) ?: return
            val ids = manager.getAppWidgetIds(ComponentName(context, TodayWidget::class.java))
            if (ids.isEmpty()) return
            val views = buildViews(context)
            for (id in ids) manager.updateAppWidget(id, views)
        }

        /**
         * ponytail: a naptár-lekérdezés itt a fő szálon fut (a receiver amúgy is
         * ott ébred). Egy nap eseményei néhány sor, ez ezredmásodpercek kérdése.
         * Ha valaha lassú lenne, a `goAsync()` + háttérszál a következő lépcső.
         */
        private fun buildViews(context: Context): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.widget_today)
            // Az egész lapra: koppintásra megnyílik az app. Hidegindításkor az
            // Események fülön indul (az a kezdőútvonal). ponytail: ha az app már
            // fut egy másik fülön, oda tér vissza — a fülre ugráshoz deep link
            // kellene a go_routerbe.
            views.setOnClickPendingIntent(R.id.widget_root, openApp(context))

            if (!hasCalendarPermission(context)) {
                // A widget maga nem tud engedélyt kérni — csak elküldeni oda,
                // ahol meg lehet adni.
                return views.withNote(context, "Koppints a naptár engedélyezéséhez")
            }

            val events = context.contentResolver.queryInstances(todayStart(), tomorrowStart())
            if (events.isEmpty()) return views.withNote(context, "Ma nincs eseményed")

            for (i in 0 until MAX_ROWS) {
                val event = events.getOrNull(i)
                if (event == null) {
                    views.setViewVisibility(ROWS[i], View.GONE)
                    continue
                }
                views.setViewVisibility(ROWS[i], View.VISIBLE)
                views.setTextViewText(TIMES[i], timeLabel(context, event))
                views.setTextViewText(TITLES[i], titleOf(event))
            }

            val extra = events.size - MAX_ROWS
            views.setViewVisibility(
                R.id.widget_note,
                if (extra > 0) View.VISIBLE else View.GONE,
            )
            if (extra > 0) views.setTextViewText(R.id.widget_note, "+$extra további")
            return views
        }

        /** Üzenet a sorok helyett: üres nap vagy hiányzó engedély. */
        private fun RemoteViews.withNote(context: Context, note: String): RemoteViews {
            for (row in ROWS) setViewVisibility(row, View.GONE)
            setViewVisibility(R.id.widget_note, View.VISIBLE)
            setTextViewText(R.id.widget_note, note)
            return this
        }

        /**
         * `14:30`, illetve egész naposnál `Egész nap`. A rendszer 12/24 órás
         * beállítását követi.
         */
        private fun timeLabel(context: Context, event: Map<String, Any?>): String {
            if (event["allDay"] == true) return "Egész nap"
            val begin = event["begin"] as? Long ?: return ""
            return DateFormat.getTimeFormat(context).format(Date(begin))
        }

        /** Ugyanaz a helyettesítő szöveg, mint a Dart oldalon. */
        private fun titleOf(event: Map<String, Any?>): String {
            val title = (event["title"] as? String)?.trim()
            return if (title.isNullOrEmpty()) "(névtelen esemény)" else title
        }

        /**
         * A mai nap kezdete helyi időben. A naptár egész napos eseményt UTC
         * éjféllel jelöl, ami pozitív eltolású zónában (mint a magyar) ugyanennek
         * a napnak a délelőttjére esik — tehát beleesik ebbe az ablakba.
         */
        private fun todayStart(): Long = startOfToday().timeInMillis

        /** A holnapi nap kezdete — nyári időszámítás-váltáskor is pontos (a nap
         * ilyenkor 23 vagy 25 órás, nem lehet 24-et hozzáadni). */
        private fun tomorrowStart(): Long = startOfToday()
            .apply { add(Calendar.DAY_OF_MONTH, 1) }
            .timeInMillis

        private fun startOfToday(): Calendar = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }

        private fun hasCalendarPermission(context: Context): Boolean =
            ContextCompat.checkSelfPermission(context, Manifest.permission.READ_CALENDAR) ==
                PackageManager.PERMISSION_GRANTED

        private fun openApp(context: Context): PendingIntent {
            val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)
                ?: Intent(context, MainActivity::class.java)
            return PendingIntent.getActivity(
                context,
                0,
                intent,
                // Az FLAG_IMMUTABLE Android 12 óta kötelező a PendingIntenteken.
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
        }
    }
}
