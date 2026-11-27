
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
  LessonPeriod({required this.number, required this.start, required this.end});
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
            .map((e) => LessonEntry.fromJson(Map<String, dynamic>.from(e)))
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
          .map((e) => LessonPeriod.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return defaults();
    }
  }

  static Future<void> savePeriods(List<LessonPeriod> periods) async {
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
          .map((e) => TeacherSchedule.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveTeachers(List<TeacherSchedule> teachers) async {
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

    final backupList = await backups();
    backupList.insert(0, {
      'created': DateTime.now().toIso8601String(),
      'teachers': teachers.map((e) => e.toJson()).toList(),
    });

    if (backupList.length > 3) {
      backupList.removeRange(3, backupList.length);
    }

    final p = await SharedPreferences.getInstance();
    await p.setString(backupsKey, jsonEncode(backupList));
  }

  static Future<void> restore(int index) async {
    final backupList = await backups();
    if (index < 0 || index >= backupList.length) return;

    final teachers = (backupList[index]['teachers'] as List)
        .map((e) => TeacherSchedule.fromJson(Map<String, dynamic>.from(e)))
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
    lessons: teacher?.lessons.map((e) => e.toJson()).toList() ?? const [],
  );
}

class ScheduleImportResult {
  ScheduleImportResult(this.teachers, this.warnings);

  final List<TeacherSchedule> teachers;
  final List<String> warnings;
}

/// Excel dosyasındaki öğretmen bloklarını T.C. başlığına göre bulur.
/// Sabit öğretmen sayısı sınırı yoktur.
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

  static String _cellText(List<List<Data?>> rows, int row, int col) {
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

  static Future<ScheduleImportResult> parse(Uint8List bytes) async {
    final book = Excel.decodeBytes(bytes);

    if (book.tables.isEmpty) {
      throw Exception(
        'Excel dosyasında okunabilir çalışma sayfası bulunamadı.',
      );
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
        final end = i + 1 < starts.length ? starts[i + 1] : rows.length;

        final name = _cellText(rows, start + 5, 2);

        if (name.isEmpty) {
          warnings.add(
            '${start + 1}. satırdaki öğretmen bloğunda ad bulunamadı.',
          );
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
            'Aynı isimli öğretmen kaydı ayrı tutuldu: $displayName',
          );
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

        for (var r = start + 9; r <= start + 13 && r < end; r++) {
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
                '$day ${c}. ders hücresi çözümlenemedi.',
              );
              continue;
            }

            final className = parts[0];
            final code = parts[1];

            lessons.add(
              LessonEntry(
                day: day,
                period: c,
                className: className,
                code: code,
                subject: subjectByCode[code] ?? '',
              ),
            );
          }
        }

        final declaredTotal = int.tryParse(
          _cellText(rows, start + 14, 2),
        );

        if (lessons.isEmpty) {
          teacherWarnings.add('Haftalık ders çizelgesi bulunamadı.');
        }

        if (declaredTotal != null && declaredTotal != lessons.length) {
          teacherWarnings.add(
            'Excel toplamı $declaredTotal saat; çizelgede ${lessons.length} dolu hücre var.',
          );
        }

        teachers.add(
          TeacherSchedule(
            name: displayName,
            lessons: lessons,
            warning: teacherWarnings.join(' '),
          ),
        );

        warnings.addAll(
          teacherWarnings.map((w) => '$displayName: $w'),
        );
      }
    }

    if (teachers.isEmpty) {
      throw Exception(
        'Excel içinde T.C. başlığıyla başlayan öğretmen blokları bulunamadı.',
      );
    }

    return ScheduleImportResult(teachers, warnings);
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

    final prefs = await SharedPreferences.getInstance();

    if ((prefs.getBool('lesson_alerts_enabled_v1') ?? false) ||
        (prefs.getBool('persistent_notification_enabled_v1') ?? false)) {
      await _scheduleNotificationsForCurrentData();
    }

    if (mounted) setState(() {});
  }

  Future<void> _importSchedule() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      withData: true,
    );

    if (result == null || result.files.single.bytes == null) return;

    final file = result.files.single;
    setState(() => loading = true);

    try {
      final parsed = await TimetableExcelParser.parse(file.bytes!);

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
                    '${parsed.teachers.length} öğretmen kaydı bulundu.',
                  ),
                  const SizedBox(height: 8),
                  ...parsed.teachers.take(12).map(
                    (t) => Text(
                      '• ${t.name} — ${t.lessons.length} ders kaydı',
                    ),
                  ),
                  if (parsed.teachers.length > 12)
                    Text(
                      '… ve ${parsed.teachers.length - 12} öğretmen daha',
                    ),
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

        final prefs = await SharedPreferences.getInstance();

        if ((prefs.getBool('lesson_alerts_enabled_v1') ?? false) ||
            (prefs.getBool('persistent_notification_enabled_v1') ?? false)) {
          await _scheduleNotificationsForCurrentData();
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${teachers.length} öğretmen programı yüklendi.',
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Program dosyası okunamadı: $e'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> _restore(int i) async {
    await ScheduleStore.restore(i);
    teachers = await ScheduleStore.loadTeachers();

    final prefs = await SharedPreferences.getInstance();

    if ((prefs.getBool('lesson_alerts_enabled_v1') ?? false) ||
        (prefs.getBool('persistent_notification_enabled_v1') ?? false)) {
      await _scheduleNotificationsForCurrentData();
    }

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
        : 0
  ];

  @override
  void initState() {
    super.initState();
    _loadPinnedTeacher();

    timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() => now = DateTime.now()),
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

    if ((prefs.getBool('lesson_alerts_enabled_v1') ?? false) ||
        (prefs.getBool('persistent_notification_enabled_v1') ?? false)) {
      await _scheduleNotificationsForCurrentData();
    }

    if (!mounted) return;

    
