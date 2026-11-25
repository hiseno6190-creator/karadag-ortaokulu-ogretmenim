package tr.k12.karadag.karadag_ortaokulu

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "karadag/persistent_notification")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "schedule" -> {
                        val first = call.argument<String>("firstStart")
                        val last = call.argument<String>("lastEnd")
                        val teacherName = call.argument<String>("teacherName") ?: ""
                        val periodsJson = call.argument<String>("periodsJson") ?: "[]"
                        val lessonsJson = call.argument<String>("lessonsJson") ?: "[]"
                        if (first.isNullOrBlank() || last.isNullOrBlank()) {
                            result.error("INVALID_TIME", "İlk ve son ders saatleri gerekli", null)
                        } else {
                            SchoolDayAlarms.configure(this, first, last, teacherName, periodsJson, lessonsJson)
                            result.success(null)
                        }
                    }
                    "cancel" -> {
                        SchoolDayAlarms.cancel(this)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
