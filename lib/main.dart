import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'notification_service.dart';
import 'personal_area_page.dart';

void main() => runApp(const KaradagApp());

const brand = Color(0xFF1565C0);
const weekdays = ['Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma'];

class LessonPeriod {
  LessonPeriod({
    required this.number,
    required this.start,
    required this.end,
  });

  int number;
  String start;
  String end;

  Map<String, dynamic> toJson() => {
    'number': number,
    'start': start,
    'end': end,
  };

  factory LessonPeriod.fromJson(Map<String, dynamic> j) => LessonPeriod(
    number: (j['number'] as num).toInt(),
    start: j['start'] as String,
    end: j['end'] as String,
  );
}

class LessonEntry {
  LessonEntry({
    required this.day,
    required this.period,
    required this.className,
    required this.code,
    this.subject = '',
  });

  String day;
  int period;
  String className;
  String code;
  String subject;

  Map<String, dynamic> toJson() => {
    'day': day,
    'period': period,
    'className': className,
    'code': code,
    'subject': subject,
  };

  factory LessonEntry.fromJson(Map<String, dynamic> j) => LessonEntry(
    day: j['day'],
    period: j['period'],
    className: j['className'],
    code: j['code'],
    subject: j['subject'] ?? '',
  );
}

class TeacherSchedule {
  TeacherSchedule({
    required this.name,
    this.lessons = const [],
    this.warning = '',
  });

  String name;
  List<LessonEntry> lessons;
  String warning;

  Map<String, dynamic> toJson() => {
    'name': name,
    'lessons': lessons.map((e) => e.toJson()).toList(),
    'warning': warning,
  };

  factory TeacherSchedule.fromJson(Map<String, dynamic> j) =>
      TeacherSchedule(
        name: j['name'],
        lessons: (j['lessons'] as List)
            .map((e) => LessonEntry.fromJson(
                Map<String, dynamic>.from(e)))
            .toList(),
        warning: j['warning'] ?? '',
      );
}

class ScheduleStore {
  static const periodsKey = 'periods_v1';
  static const teachersKey = 'teachers_v1';
  static const backupsKey = 'backups_v1';

  static List<LessonPeriod> defaults() => [
    LessonPeriod(number: 1, start: '08:30', end: '09:10'),
    LessonPeriod(number: 2, start: '09:30', end: '10:10'),
    LessonPeriod(number: 3, start: '10:25', end: '11:05'),
    LessonPeriod(number: 4, start: '11:20', end: '12:00'),
    LessonPeriod(number: 5, start: '12:40', end: '13:20'),
    LessonPeriod(number: 6, start: '13:30', end: '14:10'),
    LessonPeriod(number: 7, start: '14:20', end: '15:00'),
  ];

  static Future<List<LessonPeriod>> loadPeriods() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(periodsKey);
    if (raw == null) return defaults();

    try {
      return (jsonDecode(raw) as List)
          .map((e) => LessonPeriod.fromJson(
              Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return defaults();
    }
  }

  static Future<void> savePeriods(
      List<LessonPeriod> periods) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
      periodsKey,
      jsonEncode(periods.map((e) => e.toJson()).toList()),
    );
  }

  static Future<List<TeacherSchedule>> loadTeachers() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(teachersKey);
    if (raw == null) return [];

    try {
      return (jsonDecode(raw) as List)
          .map((e) => TeacherSchedule.fromJson(
              Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveTeachers(
      List<TeacherSchedule> teachers) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
      teachersKey,
      jsonEncode(teachers.map((e) => e.toJson()).toList()),
    );
  }

  static Future<List<Map<String, dynamic>>> backups() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(backupsKey);
    if (raw == null) return [];

    try {
      return (jsonDecode(raw) as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> backupCurrent() async {
    final teachers = await loadTeachers();
    if (teachers.isEmpty) return;

    final list = await backups();
    list.insert(0, {
      'created': DateTime.now().toIso8601String(),
      'teachers': teachers.map((e) => e.toJson()).toList(),
    });

    if (list.length > 3) {
      list.removeRange(3, list.length);
    }

    final p = await SharedPreferences.getInstance();
    await p.setString(backupsKey, jsonEncode(list));
  }

  static Future<void> restore(int index) async {
    final list = await backups();
    if (index < 0 || index >= list.length) return;

    final teachers = (list[index]['teachers'] as List)
        .map((e) => TeacherSchedule.fromJson(
            Map<String, dynamic>.from(e)))
        .toList();

    await saveTeachers(teachers);
  }
}

Future<void> _scheduleNotificationsForCurrentData() async {
  final periods = await ScheduleStore.loadPeriods();
  final teachers = await ScheduleStore.loadTeachers();
  final prefs = await SharedPreferences.getInstance();

  final pinned = prefs.getString('pinned_teacher_v1');
  final matches = teachers.where((t) => t.name == pinned).toList();

  final teacher = matches.isNotEmpty
      ? matches.first
      : (teachers.isNotEmpty ? teachers.first : null);

  await NotificationService.instance.scheduleWeekdayNotifications(
    periods.map((p) => p.toJson()).toList(),
    teacherName: teacher?.name ?? '',
    lessons: teacher?.lessons.map((e) => e.toJson()).toList() ?? [],
  );
}

class ExcelImportResult {
  ExcelImportResult(this.teachers, this.warnings);

  final List<TeacherSchedule> teachers;
  final List<String> warnings;
}

class TimetableExcelParser {
  static const _days = <String, String>{
    'Pazartesi': 'Pazartesi',
    'Salı': 'Salı',
    'Sali': 'Salı',
    'Çarşamba': 'Çarşamba',
    'Carsamba': 'Çarşamba',
    'Perşembe': 'Perşembe',
    'Persembe': 'Perşembe',
    'Cuma': 'Cuma',
  };

  static String _cellText(
      List<List<Data?>> rows, int row, int col) {
    if (row < 0 ||
        row >= rows.length ||
        col < 0 ||
        col >= rows[row].length) {
      return '';
    }

    final value = rows[row][col]?.value;
    if (value == null) return '';

    try {
      final inner = (value as dynamic).value;
      if (inner != null) return inner.toString().trim();
    } catch (_) {}

    return value.toString().trim();
  }

  static String _key(String value) => value
      .trim()
      .replaceAll('İ', 'i')
      .replaceAll('I', 'ı')
      .toLowerCase();

  static Future<ExcelImportResult> parse(
      Uint8List bytes) async {
    final book = Excel.decodeBytes(bytes);

    if (book.tables.isEmpty) {
      throw Exception(
          'Excel dosyasında okunabilir çalışma sayfası bulunamadı.');
    }

    final teachers = <TeacherSchedule>[];
    final warnings = <String>[];
    final seen = <String>{};

    for (final sheet in book.tables.values) {
      final rows = sheet.rows;
      final starts = <int>[];

      for (var r = 0; r < rows.length; r++) {
        if (_cellText(rows, r, 0).toUpperCase() == 'T.C.') {
          starts.add(r);
        }
      }

      for (var i = 0; i < starts.length; i++) {
        final start = starts[i];
        final end =
            i + 1 < starts.length ? starts[i + 1] : rows.length;

        final name = _cellText(rows, start + 5, 2);

        if (name.isEmpty) {
          warnings.add(
              '${start + 1}. satırdaki öğretmen bloğunda ad bulunamadı.');
          continue;
        }

        var displayName = name;
        var duplicateNumber = 2;

        while (!seen.add(_key(displayName))) {
          displayName = '$name ($duplicateNumber)';
          duplicateNumber++;
        }

        if (displayName != name) {
          warnings.add(
              'Aynı isimli öğretmen kaydı ayrı tutuldu: $displayName');
        }

        final subjectByCode = <String, String>{};

        for (var r = start + 16; r < end; r++) {
          final code = _cellText(rows, r, 5);
          final subject = _cellText(rows, r, 7);

          if (code.isNotEmpty &&
              subject.isNotEmpty &&
              code != 'Ders Kodu') {
            subjectByCode.putIfAbsent(code, () => subject);
          }
        }

        final lessons = <LessonEntry>[];
        final teacherWarnings = <String>[];

        for (var r = start + 9;
            r <= start + 13 && r < end;
            r++) {
          final rawDay = _cellText(rows, r, 0);
          final day = _days[rawDay];

          if (day == null) continue;

          for (var c = 1; c <= 7; c++) {
            final raw = _cellText(rows, r, c);
            if (raw.isEmpty) continue;

            final parts = raw
                .split(RegExp(r'\r?\n'))
                .map((x) => x.trim())
                .where((x) => x.isNotEmpty)
                .toList();

            if (parts.length < 2) {
              teacherWarnings.add(
                  '$day ${c}. ders hücresi çözümlenemedi.');
              continue;
            }

            final className = parts[0];
            final code = parts[1];

            lessons.add(LessonEntry(
              day: day,
              period: c,
              className: className,
              code: code,
              subject: subjectByCode[code] ?? '',
            ));
          }
        }

        final declaredTotal =
            int.tryParse(_cellText(rows, start + 14, 2));

        if (lessons.isEmpty) {
          teacherWarnings.add('Haftalık ders çizelgesi bulunamadı.');
        }

        if (declaredTotal != null &&
            declaredTotal != lessons.length) {
          teacherWarnings.add(
              'Excel toplamı $declaredTotal saat; çizelgede ${lessons.length} dolu hücre var.');
        }

        teachers.add(TeacherSchedule(
          name: displayName,
          lessons: lessons,
          warning: teacherWarnings.join(' '),
        ));

        warnings.addAll(
            teacherWarnings.map((w) => '$displayName: $w'));
      }
    }

    if (teachers.isEmpty) {
      throw Exception(
          'Excel içinde T.C. başlığıyla başlayan öğretmen blokları bulunamadı.');
    }

    return ExcelImportResult(teachers, warnings);
  }
}

class KaradagApp extends StatelessWidget {
  const KaradagApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Karadağ Ortaokulu',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: brand),
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFFF7F9F8),
    ),
    home: const MainShell(),
  );
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int tab = 0;
  List<LessonPeriod> periods = ScheduleStore.defaults();
  List<TeacherSchedule> teachers = [];
  List<Map<String, dynamic>> backups = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    periods = await ScheduleStore.loadPeriods();
    teachers = await ScheduleStore.loadTeachers();
    backups = await ScheduleStore.backups();

    if (mounted) {
      setState(() => loading = false);
    }
  }

  Future<void> _savePeriods() async {
    await ScheduleStore.savePeriods(periods);
    await _scheduleNotificationsForCurrentData();

    if (mounted) setState(() {});
  }

  Future<void> _importSchedule() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      withData: true,
    );

    if (result == null || result.files.single.bytes == null) {
      return;
    }

    setState(() => loading = true);

    try {
      final parsed = await TimetableExcelParser.parse(
          result.files.single.bytes!);

      if (!mounted) return;

      if (parsed.teachers.isEmpty) {
        throw Exception('Dosyada öğretmen kaydı bulunamadı.');
      }

      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Excel dosyası önizleme'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      '${parsed.teachers.length} öğretmen kaydı bulundu.'),
                  const SizedBox(height: 8),
                  ...parsed.teachers.take(12).map(
                    (t) => Text(
                        '• ${t.name} — ${t.lessons.length} ders kaydı'),
                  ),
                  if (parsed.teachers.length > 12)
                    Text(
                        '… ve ${parsed.teachers.length - 12} öğretmen daha'),
                  const SizedBox(height: 8),
                  Text(
                    '${parsed.warnings.length} uyarı bulundu.',
                    style: TextStyle(
                      color: parsed.warnings.isEmpty
                          ? Colors.green
                          : Colors.orange,
                    ),
                  ),
                  if (parsed.warnings.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    ...parsed.warnings.take(8).map(
                      (w) => Text(
                        '• $w',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  const Text(
                    'Onaylarsan mevcut program yedeklenecek. Ders saatleri ayarların korunacak.',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Programı etkinleştir'),
            ),
          ],
        ),
      );

      if (ok == true) {
        await ScheduleStore.backupCurrent();
        await ScheduleStore.saveTeachers(parsed.teachers);

        teachers = parsed.teachers;
        backups = await ScheduleStore.backups();

        await _scheduleNotificationsForCurrentData();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  '${teachers.length} öğretmen programı yüklendi.'),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Excel dosyası okunamadı: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _restore(int i) async {
    await ScheduleStore.restore(i);
    teachers = await ScheduleStore.loadTeachers();
    await _scheduleNotificationsForCurrentData();

    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomePage(teachers: teachers, periods: periods),
      PeriodSettingsPage(
        periods: periods,
        onChanged: (p) async {
          periods = p;
          await _savePeriods();
        },
      ),
      ProgramPage(
        teachers: teachers,
        periods: periods,
        backups: backups,
        onImport: _importSchedule,
        onRestore: _restore,
      ),
      const PersonalAreaPage(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Karadağ Ortaokulu',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: brand,
        foregroundColor: Colors.white,
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : IndexedStack(index: tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (v) => setState(() => tab = v),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Ana Sayfa',
          ),
          NavigationDestination(
            icon: Icon(Icons.schedule_outlined),
            selectedIcon: Icon(Icons.schedule),
            label: 'Ders Saatleri',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Program',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Kişisel Alan',
          ),
        ],
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.teachers,
    required this.periods,
  });

  final List<TeacherSchedule> teachers;
  final List<LessonPeriod> periods;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Timer? timer;
  DateTime now = DateTime.now();
  String? selectedTeacher;
  final TextEditingController teacherSearch = TextEditingController();

  String day = weekdays[
      DateTime.now().weekday - 1 < 5
          ? DateTime.now().weekday - 1
          : 0];

  @override
  void initState() {
    super.initState();
    _loadPinnedTeacher();
    timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        if (mounted) {
          setState(() => now = DateTime.now());
        }
      },
    );
  }

  Future<void> _loadPinnedTeacher() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('pinned_teacher_v1');

    if (!mounted || saved == null) return;

    if (widget.teachers.any((t) => t.name == saved)) {
      setState(() => selectedTeacher = saved);
    }
  }

  Future<void> _pinTeacher() async {
    final name = teacher?.name;
    if (name == null) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pinned_teacher_v1', name);

    await _scheduleNotificationsForCurrentData();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            '$name sabitlenen öğretmen olarak kaydedildi.'),
      ),
    );
  }

  @override
  void dispose() {
    timer?.cancel();
    teacherSearch.dispose();
    super.dispose();
  }

  TeacherSchedule? get teacher {
    if (widget.teachers.isEmpty) return null;

    final found = widget.teachers
        .where((t) => t.name == selectedTeacher)
        .toList();

    return found.isNotEmpty ? found.first : widget.teachers.first;
  }

  int _mins(String value) {
    final p = value.split(':');
    return int.parse(p[0]) * 60 + int.parse(p[1]);
  }

  String _duration(int seconds) {
    if (seconds < 0) seconds = 0;
    final d = Duration(seconds: seconds);

    return '${d.inHours.toString().padLeft(2, '0')}:'
        '${(d.inMinutes % 60).toString().padLeft(2, '0')}:'
        '${(d.inSeconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final dayLessons =
        teacher?.lessons
                .where((e) => e.day == day)
                .toList() ??
            <LessonEntry>[];

    dayLessons.sort((a, b) => a.period.compareTo(b.period));

    final currentMinutes = now.hour * 60 + now.minute;
    LessonPeriod? currentPeriod;
    LessonEntry? currentLesson;
    LessonPeriod? nextPeriod;
    LessonEntry? nextLesson;
    var status = 'Bugün için ders kaydı bulunmuyor.';
    var remainingSeconds = 0;

    for (final lesson in dayLessons) {
      final matches = widget.periods
          .where((p) => p.number == lesson.period)
          .toList();
      if (matches.isEmpty) continue;

      final period = matches.first;
      final start = _mins(period.start);
      final end = _mins(period.end);

      if (currentMinutes >= start && currentMinutes < end) {
        currentPeriod = period;
        currentLesson = lesson;
        remainingSeconds =
            (end * 60) - (now.hour * 3600 + now.minute * 60 + now.second);
        status = 'Ders devam ediyor';
        break;
      }

      if (currentMinutes < start) {
        nextPeriod = period;
        nextLesson = lesson;
        remainingSeconds =
            (start * 60) - (now.hour * 3600 + now.minute * 60 + now.second);
        status = 'Sonraki ders';
        break;
      }
    }

    if (currentPeriod == null &&
        nextPeriod == null &&
        dayLessons.isNotEmpty) {
      status = 'Bugünkü dersleriniz tamamlandı.';
    }

    final selected = teacher;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Öğretmen seçimi',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                if (widget.teachers.isEmpty)
                  const Text(
                    'Henüz program yüklenmedi. Program sekmesinden Excel dosyanızı aktarabilirsiniz.',
                  )
                else ...[
                  DropdownButtonFormField<String>(
                    value: widget.teachers.any(
                            (t) => t.name == selectedTeacher)
                        ? selectedTeacher
                        : widget.teachers.first.name,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Öğretmen',
                    ),
                    items: widget.teachers
                        .map(
                          (t) => DropdownMenuItem(
                            value: t.name,
                            child: Text(
                              t.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      setState(() => selectedTeacher = value);
                    },
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _pinTeacher,
                      icon: const Icon(Icons.push_pin_outlined),
                      label: const Text('Öğretmenimi sabitle'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          color: const Color(0xFFE8F2FF),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                Text(
                  DateFormat('d MMMM yyyy', 'tr_TR').format(now),
                  style: const TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 4),
                Text(
                  weekdays[now.weekday >= 1 && now.weekday <= 5
                      ? now.weekday - 1
                      : 0],
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: brand,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  DateFormat('HH:mm:ss').format(now),
                  style: const TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.bold,
                    color: brand,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  status,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (currentLesson != null && currentPeriod != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    '${currentLesson.subject.isNotEmpty ? currentLesson.subject : currentLesson.code}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                  Text(
                    '${currentLesson.className} · ${currentLesson.period}. ders',
                  ),
                  const SizedBox(height: 8),
                  const Text('Dersin bitmesine kalan süre'),
                  Text(
                    _duration(remainingSeconds),
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                ] else if (nextLesson != null && nextPeriod != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    '${nextLesson.subject.isNotEmpty ? nextLesson.subject : nextLesson.code}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: brand,
                    ),
                  ),
                  Text(
                    '${nextLesson.className} · ${nextLesson.period}. ders · ${nextPeriod.start}',
                  ),
                  const SizedBox(height: 8),
                  const Text('Derse başlamasına kalan süre'),
                  Text(
                    _duration(remainingSeconds),
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                      color: brand,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Haftalık ders programı',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            DropdownButton<String>(
              value: day,
              items: weekdays
                  .map((d) => DropdownMenuItem(
                        value: d,
                        child: Text(d),
                      ))
                  .toList(),
              onChanged: (value) {
                if (value != null) setState(() => day = value);
              },
            ),
          ],
        ),
        if (selected == null || dayLessons.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('Seçilen gün için ders kaydı bulunmuyor.'),
            ),
          )
        else
          ...dayLessons.map((lesson) {
            final found = widget.periods
                .where((p) => p.number == lesson.period)
                .toList();
            final period = found.isEmpty ? null : found.first;

            return Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFFE3F0FF),
                  child: Text(
                    '${lesson.period}',
                    style: const TextStyle(
                      color: brand,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                title: Text(
                  lesson.subject.isNotEmpty
                      ? lesson.subject
                      : lesson.code,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  '${lesson.className} · ${period?.start ?? '--:--'} - ${period?.end ?? '--:--'}',
                ),
                trailing: const Icon(Icons.school_outlined),
              ),
            );
          }),
        if (selected?.warning.isNotEmpty == true) ...[
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                selected!.warning,
                style: const TextStyle(color: Colors.deepOrange),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class PeriodSettingsPage extends StatelessWidget {
  const PeriodSettingsPage({
    super.key,
    required this.periods,
    required this.onChanged,
  });

  final List<LessonPeriod> periods;
  final Future<void> Function(List<LessonPeriod>) onChanged;

  Future<void> _editTime(
    BuildContext context,
    LessonPeriod period,
    bool isStart,
  ) async {
    final current = (isStart ? period.start : period.end).split(':');
    final initial = TimeOfDay(
      hour: int.tryParse(current[0]) ?? 8,
      minute: int.tryParse(current[1]) ?? 30,
    );

    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
    );

    if (picked == null) return;

    final updated = periods
        .map(
          (p) => LessonPeriod(
            number: p.number,
            start: p.number == period.number && isStart
                ? '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}'
                : p.start,
            end: p.number == period.number && !isStart
                ? '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}'
                : p.end,
          ),
        )
        .toList();

    await onChanged(updated);
  }

  @override
  Widget build(BuildContext context) {
    final sorted = [...periods]
      ..sort((a, b) => a.number.compareTo(b.number));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Ders saatleri',
          style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        const Text(
          'Saatleri değiştirmek için başlangıç veya bitiş saatine dokunun. Değişiklikler cihazınıza kaydedilir.',
          style: TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 12),
        ...sorted.map(
          (period) => Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 8,
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: const Color(0xFFE3F0FF),
                    child: Text(
                      '${period.number}',
                      style: const TextStyle(
                        color: brand,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${period.number}. Ders',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _editTime(
                      context,
                      period,
                      true,
                    ),
                    child: Text(period.start),
                  ),
                  const Text('-'),
                  TextButton(
                    onPressed: () => _editTime(
                      context,
                      period,
                      false,
                    ),
                    child: Text(period.end),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Not: Bu ekrandaki saatler tüm hafta için ortaktır. Günlere göre ayrı saat tanımlama özelliği henüz eklenmedi.',
          style: TextStyle(fontSize: 12, color: Colors.black54),
        ),
      ],
    );
  }
}

class ProgramPage extends StatefulWidget {
  const ProgramPage({
    super.key,
    required this.teachers,
    required this.periods,
    required this.backups,
    required this.onImport,
    required this.onRestore,
  });

  final List<TeacherSchedule> teachers;
  final List<LessonPeriod> periods;
  final List<Map<String, dynamic>> backups;
  final Future<void> Function() onImport;
  final Future<void> Function(int) onRestore;

  @override
  State<ProgramPage> createState() => _ProgramPageState();
}

class _ProgramPageState extends State<ProgramPage> {
  bool lessonAlertsEnabled = false;
  bool persistentNotificationEnabled = false;
  bool settingsLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    if (!mounted) return;

    setState(() {
      lessonAlertsEnabled =
          prefs.getBool('lesson_alerts_enabled_v1') ?? false;
      persistentNotificationEnabled =
          prefs.getBool('persistent_notification_enabled_v1') ?? false;
      settingsLoaded = true;
    });
  }

  Future<void> _toggleLessonAlerts(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('lesson_alerts_enabled_v1', value);

    if (!mounted) return;
    setState(() => lessonAlertsEnabled = value);

    await _refreshNotifications();
  }

  Future<void> _togglePersistentNotification(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('persistent_notification_enabled_v1', value);

    if (!mounted) return;
    setState(() => persistentNotificationEnabled = value);

    if (value) {
      await NotificationService.instance.requestPermission();
    }

    await _refreshNotifications();
  }

  Future<void> _refreshNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    final pinned = prefs.getString('pinned_teacher_v1');

    final matches = widget.teachers
        .where((t) => t.name == pinned)
        .toList();

    final teacher = matches.isNotEmpty
        ? matches.first
        : (widget.teachers.isNotEmpty
            ? widget.teachers.first
            : null);

    await NotificationService.instance.scheduleWeekdayNotifications(
      widget.periods.map((p) => p.toJson()).toList(),
      teacherName: teacher?.name ?? '',
      lessons: teacher?.lessons.map((e) => e.toJson()).toList() ?? [],
    );
  }

  Future<void> _confirmRestore(int index) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Yedek geri yüklensin mi?'),
        content: const Text(
          'Mevcut programın üzerine yazılacak.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Geri yükle'),
          ),
        ],
      ),
    );

    if (yes == true) {
      await widget.onRestore(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Bildirim ayarları',
          style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        const Text(
          'İki bildirim türünü birbirinden bağımsız açıp kapatabilirsiniz.',
          style: TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              SwitchListTile(
                secondary: const Icon(
                  Icons.notifications_active_outlined,
                  color: brand,
                ),
                title: const Text('1 dakika bildirimi'),
                subtitle: const Text(
                  'Ders başlamadan ve bitmeden bir dakika önce uyarı verir. Bildirim 5 dakika sonra kaybolur.',
                ),
                value: lessonAlertsEnabled,
                onChanged: settingsLoaded
                    ? _toggleLessonAlerts
                    : null,
              ),
              const Divider(height: 1),
              SwitchListTile(
                secondary: const Icon(
                  Icons.school_outlined,
                  color: brand,
                ),
                title: const Text('30 dakika kalıcı bildirim'),
                subtitle: const Text(
                  'Sabitlenen öğretmenin ilk dersinden 30 dakika önce başlar, son dersinden 10 dakika sonra sona erer.',
                ),
                value: persistentNotificationEnabled,
                onChanged: settingsLoaded
                    ? _togglePersistentNotification
                    : null,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const Icon(
                  Icons.table_view,
                  size: 42,
                  color: brand,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Yeni ders programı ekle',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Excel (.xlsx) dosyanızı seçerek programı aktarabilirsiniz. Öğretmen sayısı için sabit bir üst sınır yoktur.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: widget.onImport,
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Excel dosyası seç'),
                  ),
                ),
              ],
            ),
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.people_alt_outlined),
            title: const Text('Aktif öğretmen sayısı'),
            trailing: Text('${ww
 
