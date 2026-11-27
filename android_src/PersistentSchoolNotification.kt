package tr.k12.karadag.karadag_ortaokulu

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar

private const val PREFS = "karadag_persistent_notification"
private const val ENABLED = "enabled"
private const val TEACHER = "teacher"
private const val PERIODS_JSON = "periods_json"
private const val LESSONS_JSON = "lessons_json"
private const val DAILY_SCHEDULE_JSON = "daily_schedule_json"
private const val CHANNEL_ID = "karadag_school_day"
private const val NOTIFICATION_ID = 7301

private val schoolDays = mapOf(
    Calendar.MONDAY to "Pazartesi",
    Calendar.TUESDAY to "Salı",
    Calendar.WEDNESDAY to "Çarşamba",
    Calendar.THURSDAY to "Perşembe",
    Calendar.FRIDAY to "Cuma"
)

object SchoolDayAlarms {

    fun configure(
        context: Context,
        firstStart: String,
        lastEnd: String,
        teacherName: String,
        periodsJson: String,
        lessonsJson: String,
        dailyScheduleJson: String
    ) {
        val dailySchedule = try {
            JSONObject(dailyScheduleJson)
        } catch (_: Exception) {
            JSONObject()
        }

        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

        prefs.edit()
            .putString(TEACHER, teacherName)
            .putString(PERIODS_JSON, periodsJson)
            .putString(LESSONS_JSON, lessonsJson)
            .putString(DAILY_SCHEDULE_JSON, dailySchedule.toString())
            .putBoolean(ENABLED, dailySchedule.length() > 0)
            .apply()

        cancelAlarms(context)

        if (dailySchedule.length() == 0) {
            stopNotificationService(context)
            return
        }

        for ((dayNumber, dayName) in schoolDays) {
            if (dailySchedule.has(dayName)) {
                scheduleNext(context, dayNumber, true)
                scheduleNext(context, dayNumber, false)
            }
        }

        startIfSchoolDayIsActive(context)
    }

    fun cancel(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(ENABLED, false)
            .apply()

        cancelAlarms(context)
        stopNotificationService(context)
    }

    private fun stopNotificationService(context: Context) {
        context.stopService(
            Intent(context, SchoolDayNotificationService::class.java)
        )
    }

    private fun startNotificationService(context: Context) {
        val service = Intent(
            context,
            SchoolDayNotificationService::class.java
        )

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(service)
            } else {
                context.startService(service)
            }
        } catch (_: Exception) {
        }
    }

    private fun parseMinutes(value: String): Int? {
        val parts = value.split(":")
        if (parts.size != 2) return null

        val hour = parts[0].toIntOrNull() ?: return null
        val minute = parts[1].toIntOrNull() ?: return null

        if (hour !in 0..23 || minute !in 0..59) return null

        return hour * 60 + minute
    }

    fun isWithinSchoolWindow(context: Context): Boolean {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

        if (!prefs.getBoolean(ENABLED, false)) return false

        val dailySchedule = try {
            JSONObject(prefs.getString(DAILY_SCHEDULE_JSON, "{}") ?: "{}")
        } catch (_: Exception) {
            JSONObject()
        }

        val calendar = Calendar.getInstance()
        val dayName = schoolDays[calendar.get(Calendar.DAY_OF_WEEK)] ?: return false
        val daySchedule = dailySchedule.optJSONObject(dayName) ?: return false

        val firstStart = parseMinutes(daySchedule.optString("firstStart")) ?: return false
        val lastEnd = parseMinutes(daySchedule.optString("lastEnd")) ?: return false

        val now = calendar.get(Calendar.HOUR_OF_DAY) * 60 +
            calendar.get(Calendar.MINUTE)

        return now >= firstStart - 30 && now < lastEnd + 10
    }

    private fun startIfSchoolDayIsActive(context: Context) {
        if (isWithinSchoolWindow(context)) {
            startNotificationService(context)
        } else {
            stopNotificationService(context)
        }
    }

    private fun cancelAlarms(context: Context) {
        val alarm = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

        for (day in Calendar.MONDAY..Calendar.FRIDAY) {
            alarm.cancel(pendingIntent(context, day, true))
            alarm.cancel(pendingIntent(context, day, false))
        }
    }

    fun scheduleNext(context: Context, day: Int, start: Boolean) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

        if (!prefs.getBoolean(ENABLED, false)) return

        val dayName = schoolDays[day] ?: return

        val dailySchedule = try {
            JSONObject(prefs.getString(DAILY_SCHEDULE_JSON, "{}") ?: "{}")
        } catch (_: Exception) {
            JSONObject()
        }

        val daySchedule = dailySchedule.optJSONObject(dayName) ?: return

        val rawTime = daySchedule.optString(
            if (start) "firstStart" else "lastEnd"
        )

        val baseMinutes = parseMinutes(rawTime) ?: return

        val calendar = Calendar.getInstance().apply {
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
            set(Calendar.HOUR_OF_DAY, baseMinutes / 60)
            set(Calendar.MINUTE, baseMinutes % 60)
            add(Calendar.MINUTE, if (start) -30 else 10)

            while (
                get(Calendar.DAY_OF_WEEK) != day ||
                timeInMillis <= System.currentTimeMillis()
            ) {
                add(Calendar.DAY_OF_YEAR, 1)
            }
        }

        val alarm = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = pendingIntent(context, day, start)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            alarm.setAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                calendar.timeInMillis,
                intent
            )
        } else {
            alarm.set(
                AlarmManager.RTC_WAKEUP,
                calendar.timeInMillis,
                intent
            )
        }
    }

    private fun pendingIntent(
        context: Context,
        day: Int,
        start: Boolean
    ): PendingIntent {
        val intent = Intent(context, SchoolDayAlarmReceiver::class.java)
            .putExtra("day", day)
            .putExtra("start", start)

        val requestCode = day * 10 + if (start) 1 else 2

        return PendingIntent.getBroadcast(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or
                if (Build.VERSION.SDK_INT >= 23) {
                    PendingIntent.FLAG_IMMUTABLE
                } else {
                    0
                }
        )
    }

    fun rescheduleAll(context: Context) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

        if (!prefs.getBoolean(ENABLED, false)) return

        val dailySchedule = try {
            JSONObject(prefs.getString(DAILY_SCHEDULE_JSON, "{}") ?: "{}")
        } catch (_: Exception) {
            JSONObject()
        }

        for ((dayNumber, dayName) in schoolDays) {
            if (dailySchedule.has(dayName)) {
                scheduleNext(context, dayNumber, true)
                scheduleNext(context, dayNumber, false)
            }
        }

        startIfSchoolDayIsActive(context)
    }
}

class SchoolDayAlarmReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val day = intent.getIntExtra("day", -1)
        val start = intent.getBooleanExtra("start", false)

        if (start) {
            val service = Intent(
                context,
                SchoolDayNotificationService::class.java
            )

            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(service)
                } else {
                    context.startService(service)
                }
            } catch (_: Exception) {
            }
        } else {
            context.stopService(
                Intent(context, SchoolDayNotificationService::class.java)
            )
        }

        if (day in Calendar.MONDAY..Calendar.FRIDAY) {
            SchoolDayAlarms.scheduleNext(context, day, start)
        }
    }
}

class SchoolDayBootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (
            intent.action == Intent.ACTION_BOOT_COMPLETED ||
            intent.action == Intent.ACTION_MY_PACKAGE_REPLACED
        ) {
            SchoolDayAlarms.rescheduleAll(context)
        }
    }
}

class SchoolDayNotificationService : Service() {

    private val handler = Handler(Looper.getMainLooper())

    private val refresh = object : Runnable {
        override fun run() {
            if (!SchoolDayAlarms.isWithinSchoolWindow(this@SchoolDayNotificationService)) {
                stopSelf()
                return
            }

            val manager =
                getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            manager.notify(NOTIFICATION_ID, buildNotification())

            handler.postDelayed(this, 15_000L)
        }
    }

    override fun onCreate() {
        super.onCreate()
        createChannel()
        startForeground(NOTIFICATION_ID, buildNotification())
        handler.removeCallbacks(refresh)
        handler.postDelayed(refresh, 15_000L)
    }

    override fun onStartCommand(
        intent: Intent?,
        flags: Int,
        startId: Int
    ): Int {
        if (!SchoolDayAlarms.isWithinSchoolWindow(this)) {
            stopSelf()
            return START_NOT_STICKY
        }

        val manager =
            getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        manager.notify(NOTIFICATION_ID, buildNotification())

        return START_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacks(refresh)
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Okul günü ders takibi",
                NotificationManager.IMPORTANCE_LOW
            )

            channel.description =
                "Seçili öğretmenin ders ve teneffüs bilgilerini gösterir"

            channel.lockscreenVisibility = Notification.VISIBILITY_PUBLIC

            getSystemService(NotificationManager::class.java)
                .createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        val prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)

        val teacher = prefs.getString(TEACHER, "") ?: ""
        val periods = JSONArray(
            prefs.getString(PERIODS_JSON, "[]") ?: "[]"
        )
        val lessons = JSONArray(
            prefs.getString(LESSONS_JSON, "[]") ?: "[]"
        )

        val calendar = Calendar.getInstance()
        val dayName = schoolDays[calendar.get(Calendar.DAY_OF_WEEK)] ?: ""

        val nowMinute =
            calendar.get(Calendar.HOUR_OF_DAY) * 60 +
                calendar.get(Calendar.MINUTE)

        fun lessonFor(periodNumber: Int): JSONObject? {
            for (i in 0 until lessons.length()) {
                val item = lessons.optJSONObject(i) ?: continue

                if (
                    item.optString("day") == dayName &&
                    item.optInt("period") == periodNumber
                ) {
                    return item
                }
            }
            return null
        }

        val teacherPeriods = mutableListOf<JSONObject>()

        for (i in 0 until periods.length()) {
            val period = periods.optJSONObject(i) ?: continue
            val number = period.optInt("number")

            if (lessonFor(number) != null) {
                teacherPeriods.add(period)
            }
        }

        teacherPeriods.sortBy {
            toMinutes(it.optString("start"))
        }

        val active = teacherPeriods.firstOrNull {
            nowMinute >= toMinutes(it.optString("start")) &&
                nowMinute < toMinutes(it.optString("end"))
        }

        val next = teacherPeriods.firstOrNull {
            toMinutes(it.optString("start")) > nowMinute
        }

        val lastPeriod = teacherPeriods.lastOrNull()
        val lastEnd = lastPeriod?.let {
            toMinutes(it.optString("end"))
        } ?: -1

        val heading: String
        val detail: String

        when {
            dayName.isEmpty() -> {
                heading = "Hafta sonu"
                detail = "Bugün ders programınız bulunmuyor."
            }

            teacherPeriods.isEmpty() -> {
                heading = "Bugün dersiniz yok"
                detail = "İyi dinlenmeler."
            }

            lastEnd >= 0 && nowMinute >= lastEnd -> {
                heading = "Bugünlük dersiniz bitti"
                detail =
                    "Bugünlük dersiniz bitti. Bu bildirim birazdan otomatik kapanacak."
            }

            active != null -> {
                val number = active.optInt("number")
                val entry = lessonFor(number)

                val subject = entry?.optString("subject", "")
                    ?.takeIf { it.isNotBlank() } ?: "Ders"

                val classroom = entry?.optString("className", "")
                    ?.takeIf { it.isNotBlank() } ?: ""

                val remain = (
                    toMinutes(active.optString("end")) - nowMinute
                ).coerceAtLeast(0)

                heading =
                    "$number. ders • $subject" +
                        if (classroom.isNotEmpty()) " • $classroom" else ""

                detail = "Teneffüse kalan süre: $remain dk"
            }

            next != null -> {
                val number = next.optInt("number")
                val entry = lessonFor(number)

                val subject = entry?.optString("subject", "")
                    ?.takeIf { it.isNotBlank() } ?: "Ders"

                val classroom = entry?.optString("className", "")
                    ?.takeIf { it.isNotBlank() } ?: ""

                val remain = (
                    toMinutes(next.optString("start")) - nowMinute
                ).coerceAtLeast(0)

                heading =
                    "Sıradaki: $number. ders • $subject" +
                        if (classroom.isNotEmpty()) " • $classroom" else ""

                detail = "Derse kalan süre: $remain dk"
            }

            else -> {
                heading = "Ders arası"
                detail = "Bir sonraki dersiniz için hazırlanın."
            }
        }

        val messages = listOf(
            "Her ders yeni bir fırsat, her öğrenci yeni bir umut.",
            "Sabırla anlat, sevgiyle yaklaş; küçük adımlar büyük izler bırakır.",
            "Emeğiniz geleceğe bırakılan en değerli mirastır.",
            "Bugün bir öğrencinin gününü güzelleştirebilirsiniz.",
            "Bilgi paylaşınca çoğalır. Motivasyonunuz yüksek olsun!"
        )

        val motivation =
            messages[(calendar.get(Calendar.DAY_OF_YEAR) - 1) % messages.size]

        val openApp = packageManager.getLaunchIntentForPackage(packageName)

        val contentIntent = openApp?.let {
            PendingIntent.getActivity(
                this,
                7302,
                it,
                PendingIntent.FLAG_UPDATE_CURRENT or
                    if (Build.VERSION.SDK_INT >= 23) {
                        PendingIntent.FLAG_IMMUTABLE
                    } else {
                        0
                    }
            )
        }

        val builder =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(this, CHANNEL_ID)
            } else {
                Notification.Builder(this)
            }

        val expanded = "$detail\n$teacher\n$motivation"

        return builder
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(heading)
            .setContentText(detail)
            .setStyle(Notification.BigTextStyle().bigText(expanded))
            .setCategory(Notification.CATEGORY_SERVICE)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setContentIntent(contentIntent)
            .build()
    }

    private fun toMinutes(value: String): Int {
        val parts = value.split(":")
        if (parts.size != 2) return 0

        val hour = parts[0].toIntOrNull() ?: return 0
        val minute = parts[1].toIntOrNull() ?: return 0

        return hour * 60 + minute
    }
}
