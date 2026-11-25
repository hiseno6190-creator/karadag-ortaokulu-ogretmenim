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
import android.os.IBinder
import java.util.Calendar
import java.util.Locale
import android.os.Handler
import android.os.Looper
import org.json.JSONArray

private const val PREFS = "karadag_persistent_notification"
private const val FIRST = "first_start"
private const val LAST = "last_end"
private const val ENABLED = "enabled"
private const val TEACHER = "teacher"
private const val PERIODS_JSON = "periods_json"
private const val LESSONS_JSON = "lessons_json"
private const val CHANNEL_ID = "karadag_school_day"
private const val NOTIFICATION_ID = 7301

object SchoolDayAlarms {
    fun configure(context: Context, firstStart: String, lastEnd: String, teacherName: String, periodsJson: String, lessonsJson: String) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        prefs.edit().putString(FIRST, firstStart).putString(LAST, lastEnd)
            .putString(TEACHER, teacherName).putString(PERIODS_JSON, periodsJson)
            .putString(LESSONS_JSON, lessonsJson).putBoolean(ENABLED, true).apply()
        val alarm = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        for (day in Calendar.MONDAY..Calendar.FRIDAY) {
            alarm.cancel(pendingIntent(context, day, true))
            alarm.cancel(pendingIntent(context, day, false))
        }
        for (day in Calendar.MONDAY..Calendar.FRIDAY) {
            scheduleNext(context, day, true)
            scheduleNext(context, day, false)
        }
    }

    fun cancel(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putBoolean(ENABLED, false).apply()
        val alarm = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        for (day in Calendar.MONDAY..Calendar.FRIDAY) {
            for (start in listOf(true, false)) {
                val pi = pendingIntent(context, day, start)
                alarm.cancel(pi)
            }
        }
        context.stopService(Intent(context, SchoolDayNotificationService::class.java))
    }

    fun scheduleNext(context: Context, day: Int, start: Boolean) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (!prefs.getBoolean(ENABLED, false)) return
        val raw = prefs.getString(if (start) FIRST else LAST, null) ?: return
        val parts = raw.split(":")
        if (parts.size != 2) return
        val hour = parts[0].toIntOrNull() ?: return
        val minute = parts[1].toIntOrNull() ?: return
        val cal = Calendar.getInstance().apply {
            set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
            set(Calendar.HOUR_OF_DAY, hour); set(Calendar.MINUTE, minute)
            if (start) add(Calendar.MINUTE, -30) else add(Calendar.MINUTE, 10)
            while (get(Calendar.DAY_OF_WEEK) != day || timeInMillis <= System.currentTimeMillis()) {
                add(Calendar.DAY_OF_YEAR, 1)
            }
        }
        val alarm = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pi = pendingIntent(context, day, start)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            alarm.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, cal.timeInMillis, pi)
        } else {
            alarm.set(AlarmManager.RTC_WAKEUP, cal.timeInMillis, pi)
        }
    }

    private fun pendingIntent(context: Context, day: Int, start: Boolean): PendingIntent {
        val intent = Intent(context, SchoolDayAlarmReceiver::class.java)
            .putExtra("day", day).putExtra("start", start)
        val code = day * 10 + if (start) 1 else 2
        return PendingIntent.getBroadcast(context, code, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or if (Build.VERSION.SDK_INT >= 23) PendingIntent.FLAG_IMMUTABLE else 0)
    }

    fun rescheduleAll(context: Context) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (!prefs.getBoolean(ENABLED, false)) return
        for (day in Calendar.MONDAY..Calendar.FRIDAY) {
            scheduleNext(context, day, true); scheduleNext(context, day, false)
        }
    }
}

class SchoolDayAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val day = intent.getIntExtra("day", -1)
        val start = intent.getBooleanExtra("start", false)
        if (start) {
            val service = Intent(context, SchoolDayNotificationService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) context.startForegroundService(service)
            else context.startService(service)
        } else {
            context.stopService(Intent(context, SchoolDayNotificationService::class.java))
        }
        if (day in Calendar.MONDAY..Calendar.FRIDAY) SchoolDayAlarms.scheduleNext(context, day, start)
    }
}

class SchoolDayBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED || intent.action == Intent.ACTION_MY_PACKAGE_REPLACED) {
            SchoolDayAlarms.rescheduleAll(context)
        }
    }
}

class SchoolDayNotificationService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private val refresh = object : Runnable {
        override fun run() {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.notify(NOTIFICATION_ID, buildNotification())
            handler.postDelayed(this, 60_000L)
        }
    }

    override fun onCreate() {
        super.onCreate()
        createChannel()
        startForeground(NOTIFICATION_ID, buildNotification())
        handler.postDelayed(refresh, 60_000L)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
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
            val channel = NotificationChannel(CHANNEL_ID, "Okul günü ders takibi", NotificationManager.IMPORTANCE_LOW)
            channel.description = "Ders, teneffüs ve kalan süre bilgilerini okul günü boyunca gösterir"
            channel.lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        val prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val teacher = prefs.getString(TEACHER, "") ?: ""
        val periods = JSONArray(prefs.getString(PERIODS_JSON, "[]") ?: "[]")
        val lessons = JSONArray(prefs.getString(LESSONS_JSON, "[]") ?: "[]")
        val cal = Calendar.getInstance()
        val weekday = when (cal.get(Calendar.DAY_OF_WEEK)) {
            Calendar.MONDAY -> "Pazartesi"; Calendar.TUESDAY -> "Salı"
            Calendar.WEDNESDAY -> "Çarşamba"; Calendar.THURSDAY -> "Perşembe"
            Calendar.FRIDAY -> "Cuma"; else -> ""
        }
        val nowMinute = cal.get(Calendar.HOUR_OF_DAY) * 60 + cal.get(Calendar.MINUTE)
        var active: org.json.JSONObject? = null
        var next: org.json.JSONObject? = null
        for (i in 0 until periods.length()) {
            val p = periods.optJSONObject(i) ?: continue
            val start = toMinutes(p.optString("start")); val end = toMinutes(p.optString("end"))
            if (nowMinute >= start && nowMinute < end) active = p
            if (start > nowMinute && (next == null || start < toMinutes(next!!.optString("start")))) next = p
        }
        fun lessonFor(period: Int): org.json.JSONObject? {
            for (i in 0 until lessons.length()) {
                val item = lessons.optJSONObject(i) ?: continue
                if (item.optString("day") == weekday && item.optInt("period") == period) return item
            }
            return null
        }
        val heading: String
        val detail: String
        if (weekday.isEmpty()) {
            heading = "Hafta sonu"; detail = "Bugün ders programı bulunmuyor."
        } else if (active != null) {
            val number = active!!.optInt("number")
            val entry = lessonFor(number)
            val subject = entry?.optString("subject", "")?.takeIf { it.isNotBlank() } ?: "Ders"
            val classroom = entry?.optString("className", "")?.takeIf { it.isNotBlank() } ?: ""
            val remain = (toMinutes(active!!.optString("end")) - nowMinute).coerceAtLeast(0)
            heading = "${number}. ders • $subject${if (classroom.isNotEmpty()) " • $classroom" else ""}"
            detail = "Teneffüse kalan süre: ${remain} dk"
        } else if (next != null) {
            val number = next!!.optInt("number")
            val entry = lessonFor(number)
            val subject = entry?.optString("subject", "")?.takeIf { it.isNotBlank() } ?: "Ders"
            val classroom = entry?.optString("className", "")?.takeIf { it.isNotBlank() } ?: ""
            val remain = (toMinutes(next!!.optString("start")) - nowMinute).coerceAtLeast(0)
            heading = "Sıradaki: ${number}. ders • $subject${if (classroom.isNotEmpty()) " • $classroom" else ""}"
            detail = "Derse kalan süre: ${remain} dk"
        } else {
            heading = "Bugünkü dersler tamamlandı"
            detail = "Günün emeği için teşekkürler. Yarın yeni bir başlangıç!"
        }
        val messages = listOf(
            "Her ders yeni bir fırsat, her öğrenci yeni bir umut.",
            "Sabırla anlat, sevgiyle yaklaş; küçük adımlar büyük izler bırakır.",
            "Bir öğretmenin emeği, geleceğe bırakılan en değerli mirastır.",
            "Bugün bir öğrencinin gününü güzelleştirebilirsiniz.",
            "Bilgi paylaşınca çoğalır. Motivasyonunuz yüksek olsun!"
        )
        val motivation = messages[(cal.get(Calendar.DAY_OF_YEAR) - 1) % messages.size]
        val openApp = packageManager.getLaunchIntentForPackage(packageName)
        val contentIntent = openApp?.let {
            PendingIntent.getActivity(this, 7302, it,
                PendingIntent.FLAG_UPDATE_CURRENT or if (Build.VERSION.SDK_INT >= 23) PendingIntent.FLAG_IMMUTABLE else 0)
        }
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            Notification.Builder(this, CHANNEL_ID) else Notification.Builder(this)
        val expanded = "$detail\n$motivation${if (teacher.isNotBlank()) "\n$teacher" else ""}"
        return builder.setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(heading)
            .setContentText(detail)
            .setStyle(Notification.BigTextStyle().bigText(expanded))
            .setCategory(Notification.CATEGORY_SERVICE)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setOngoing(true).setOnlyAlertOnce(true).setShowWhen(false)
            .setContentIntent(contentIntent).build()
    }

    private fun toMinutes(value: String): Int {
        val parts = value.split(":")
        return if (parts.size == 2) (parts[0].toIntOrNull() ?: 0) * 60 + (parts[1].toIntOrNull() ?: 0) else 0
    }
}
