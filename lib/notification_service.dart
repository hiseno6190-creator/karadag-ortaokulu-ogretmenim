import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
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

  Future<void> initialize() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Europe/Istanbul'));
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(const InitializationSettings(android: android));
    _initialized = true;
  }

  Future<bool> requestPermission() async {
    await initialize();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final granted = await android?.requestNotificationsPermission();
    return granted ?? true;
  }

  Future<void> cancelAll() async {
    await initialize();
    await _plugin.cancelAll();
    await _persistentChannel.invokeMethod<void>('cancel');
  }

  Future<void> scheduleWeekdayNotifications(
      List<Map<String, dynamic>> periods, {
      String teacherName = '',
      List<Map<String, dynamic>> lessons = const [],
      }) async {
    await initialize();
    if (periods.isEmpty) return;
    await _plugin.cancelAll();

    // Kalıcı bildirim: ilk dersten 30 dk önce başlar, son dersten 10 dk
    // sonra kapanır. Android tarafında alarm + foreground service kullanılır.
    final sorted = [...periods]..sort((a, b) =>
        (a['number'] as num).compareTo(b['number'] as num));
    await _persistentChannel.invokeMethod<void>('schedule', {
      'firstStart': sorted.first['start'],
      'lastEnd': sorted.last['end'],
      'teacherName': teacherName,
      'periodsJson': jsonEncode(sorted),
      'lessonsJson': jsonEncode(lessons),
    });

    const weekdays = <int>[
      DateTime.monday,
      DateTime.tuesday,
      DateTime.wednesday,
      DateTime.thursday,
      DateTime.friday,
    ];

    for (final day in weekdays) {
      for (final period in sorted) {
        final number = (period['number'] as num).toInt();
        await _scheduleWeekly(
          id: day * 1000 + number * 2,
          weekday: day,
          bellTime: period['start'] as String,
          title: 'Ders başlıyor',
          body: '$number. ders bir dakika içinde başlayacak.',
        );
        await _scheduleWeekly(
          id: day * 1000 + number * 2 + 1,
          weekday: day,
          bellTime: period['end'] as String,
          title: 'Ders bitiyor',
          body: 'Ders bitiyor, teneffüs başlıyor.',
        );
      }
    }
  }

  Future<void> _scheduleWeekly({
    required int id,
    required int weekday,
    required String bellTime,
    required String title,
    required String body,
  }) async {
    final parts = bellTime.split(':');
    final now = tz.TZDateTime.now(tz.local);
    var at = tz.TZDateTime(tz.local, now.year, now.month, now.day,
            int.parse(parts[0]), int.parse(parts[1]))
        .subtract(const Duration(minutes: 1));
    while (at.weekday != weekday || !at.isAfter(now)) {
      at = at.add(const Duration(days: 1));
    }
    await _plugin.zonedSchedule(
      id, title, body, at,
      const NotificationDetails(android: AndroidNotificationDetails(
        'karadag_ders_bildirimleri', 'Ders ve teneffüs bildirimleri',
        channelDescription: 'Ders ve teneffüs başlangıç uyarıları',
        importance: Importance.max, priority: Priority.high,
      )),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
    );
  }
}
