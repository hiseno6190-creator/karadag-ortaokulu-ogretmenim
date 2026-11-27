
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// İnternet gerektirmeyen ders uyarıları ve kalıcı okul günü bildirimi.
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  static const MethodChannel _persistentChannel =
      MethodChannel('karadag/persistent_notification');

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  static const List<int> _weekdays = [
    DateTime.monday,
    DateTime.tuesday,
    DateTime.wednesday,
    DateTime.thursday,
    DateTime.friday,
  ];

  static const Map<String, int> _dayNumbers = {
    'Pazartesi': DateTime.monday,
    'Salı': DateTime.tuesday,
    'Çarşamba': DateTime.wednesday,
    'Perşembe': DateTime.thursday,
    'Cuma': DateTime.friday,
  };

  Future<void> initialize() async {
    if (_initialized) return;

    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Europe/Istanbul'));

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');

    await _plugin.initialize(
      const InitializationSettings(android: android),
    );

    _initialized = true;
  }

  Future<bool> requestPermission() async {
    await initialize();

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    final granted = await android?.requestNotificationsPermission();

    return granted ?? true;
  }

  /// Yalnızca günlük kalıcı okul bildirimi kapatılır.
  Future<void> cancelPersistentNotification() async {
    await initialize();
    await _persistentChannel.invokeMethod<void>('cancel');
  }

  /// Seçili öğretmenin her günkü ilk ve son ders saatlerini hesaplar.
  Future<void> schedulePersistentNotification(
    List<Map<String, dynamic>> periods, {
    String teacherName = '',
    List<Map<String, dynamic>> lessons = const [],
  }) async {
    await initialize();

    if (periods.isEmpty || lessons.isEmpty) {
      await cancelPersistentNotification();
      return;
    }

    final sorted = [...periods]
      ..sort(
        (a, b) =>
            (a['number'] as num).compareTo(b['number'] as num),
      );

    final periodByNumber = <int, Map<String, dynamic>>{
      for (final period in sorted)
        (period['number'] as num).toInt(): period,
    };

    final dailySchedule = <String, Map<String, String>>{};

    for (final day in _dayNumbers.keys) {
      final dayLessons = lessons
          .where((lesson) => lesson['day']?.toString() == day)
          .toList();

      if (dayLessons.isEmpty) continue;

      dayLessons.sort(
        (a, b) =>
            (a['period'] as num).compareTo(b['period'] as num),
      );

      final firstNumber =
          (dayLessons.first['period'] as num).toInt();

      final lastNumber =
          (dayLessons.last['period'] as num).toInt();

      final firstPeriod = periodByNumber[firstNumber];
      final lastPeriod = periodByNumber[lastNumber];

      if (firstPeriod == null || lastPeriod == null) continue;

      dailySchedule[day] = {
        'firstStart': firstPeriod['start'] as String,
        'lastEnd': lastPeriod['end'] as String,
      };
    }

    if (dailySchedule.isEmpty) {
      await cancelPersistentNotification();
      return;
    }

    // Eski Android koduyla geçici uyumluluk için genel saatler de gönderilir.
    await _persistentChannel.invokeMethod<void>('schedule', {
      'firstStart': sorted.first['start'],
      'lastEnd': sorted.last['end'],
      'teacherName': teacherName,
      'periodsJson': jsonEncode(sorted),
      'lessonsJson': jsonEncode(lessons),
      'dailyScheduleJson': jsonEncode(dailySchedule),
    });
  }

  /// Yalnızca öğretmenin gerçekten dersi olan saatlere uyarı kurulur.
  Future<void> scheduleLessonAlerts(
    List<Map<String, dynamic>> periods,
    List<Map<String, dynamic>> lessons,
  ) async {
    await initialize();

    final sorted = [...periods]
      ..sort(
        (a, b) =>
            (a['number'] as num).compareTo(b['number'] as num),
      );

    // Önce eski ders uyarılarını temizle.
    // Böylece sonradan silinen derslerin eski bildirimleri kalmaz.
    for (final day in _weekdays) {
      for (var number = 1; number <= 50; number++) {
        final id = 100000 + day * 1000 + number * 2;
        await _plugin.cancel(id);
        await _plugin.cancel(id + 1);
      }
    }

    if (lessons.isEmpty || sorted.isEmpty) return;

    final scheduledKeys = <String>{};

    for (final lesson in lessons) {
      final day = _dayNumbers[lesson['day']?.toString()];
      if (day == null) continue;

      final number = (lesson['period'] as num?)?.toInt();
      if (number == null) continue;

      final key = '$day-$number';
      if (!scheduledKeys.add(key)) continue;

      final matchingPeriods = sorted.where(
        (period) => (period['number'] as num).toInt() == number,
      );

      if (matchingPeriods.isEmpty) continue;

      final period = matchingPeriods.first;
      final id = 100000 + day * 1000 + number * 2;

      // Ders başlamadan bir dakika önce.
      await _scheduleWeekly(
        id: id,
        weekday: day,
        bellTime: period['start'] as String,
        title: 'Ders başlıyor',
        body: '$number. ders bir dakika içinde başlayacak.',
      );

      // Ders bitmeden bir dakika önce.
      await _scheduleWeekly(
        id: id + 1,
        weekday: day,
        bellTime: period['end'] as String,
        title: 'Ders bitiyor',
        body: 'Ders bitiyor, teneffüs başlıyor.',
      );
    }
  }

  /// Program değişikliklerinde yalnızca açık olan bildirimleri yeniler.
  Future<void> scheduleWeekdayNotifications(
    List<Map<String, dynamic>> periods, {
    String teacherName = '',
    List<Map<String, dynamic>> lessons = const [],
  }) async {
    final prefs = await SharedPreferences.getInstance();

    final lessonAlertsEnabled =
        prefs.getBool('lesson_alerts_enabled_v1') ?? false;

    final persistentEnabled =
        prefs.getBool('persistent_notification_enabled_v1') ?? false;

    if (lessonAlertsEnabled) {
      await scheduleLessonAlerts(periods, lessons);
    } else {
      await scheduleLessonAlerts(periods, []);
    }

    if (persistentEnabled) {
      await schedulePersistentNotification(
        periods,
        teacherName: teacherName,
        lessons: lessons,
      );
    } else {
      await cancelPersistentNotification();
    }
  }

  Future<void> cancelAll() async {
    await initialize();

    await _plugin.cancelAll();
    await _persistentChannel.invokeMethod<void>('cancel');
  }

  Future<void> _scheduleWeekly({
    required int id,
    required int weekday,
    required String bellTime,
    required String title,
    required String body,
  }) async {
    final parts = bellTime.split(':');
    if (parts.length != 2) return;

    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);

    if (hour == null || minute == null) return;

    final now = tz.TZDateTime.now(tz.local);

    var at = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    ).subtract(const Duration(minutes: 1));

    while (at.weekday != weekday || !at.isAfter(now)) {
      at = at.add(const Duration(days: 1));
    }

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      at,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'karadag_ders_bildirimleri',
          'Ders ve teneffüs bildirimleri',
          channelDescription: 'Ders ve teneffüs başlangıç uyarıları',
          importance: Importance.max,
          priority: Priority.high,
          visibility: NotificationVisibility.public,
          timeoutAfter: 300000,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
    );
  }
}
