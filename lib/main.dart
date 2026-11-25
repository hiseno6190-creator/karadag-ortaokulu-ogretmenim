import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'notification_service.dart';

void main() => runApp(const KaradagApp());

const brand = Color(0xFF176B45);
const weekdays = ['Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma'];

class LessonPeriod {
  LessonPeriod({required this.number, required this.start, required this.end});
  int number;
  String start;
  String end;
  Map<String, dynamic> toJson() => {'number': number, 'start': start, 'end': end};
  factory LessonPeriod.fromJson(Map<String, dynamic> j) => LessonPeriod(
    number: (j['number'] as num).toInt(), start: j['start'] as String, end: j['end'] as String);
}

class LessonEntry {
  LessonEntry({required this.day, required this.period, required this.className, required this.code, this.subject = ''});
  String day;
  int period;
  String className;
  String code;
  String subject;
  Map<String, dynamic> toJson() => {'day': day, 'period': period, 'className': className, 'code': code, 'subject': subject};
  factory LessonEntry.fromJson(Map<String, dynamic> j) => LessonEntry(
    day: j['day'], period: j['period'], className: j['className'], code: j['code'], subject: j['subject'] ?? '');
}

class TeacherSchedule {
  TeacherSchedule({required this.name, this.lessons = const [], this.warning = ''});
  String name;
  List<LessonEntry> lessons;
  String warning;
  Map<String, dynamic> toJson() => {'name': name, 'lessons': lessons.map((e) => e.toJson()).toList(), 'warning': warning};
  factory TeacherSchedule.fromJson(Map<String, dynamic> j) => TeacherSchedule(
    name: j['name'], lessons: (j['lessons'] as List).map((e) => LessonEntry.fromJson(Map<String,dynamic>.from(e))).toList(), warning: j['warning'] ?? '');
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
    try { return (jsonDecode(raw) as List).map((e) => LessonPeriod.fromJson(Map<String,dynamic>.from(e))).toList(); }
    catch (_) { return defaults(); }
  }
  static Future<void> savePeriods(List<LessonPeriod> periods) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(periodsKey, jsonEncode(periods.map((e) => e.toJson()).toList()));
  }
  static Future<List<TeacherSchedule>> loadTeachers() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(teachersKey);
    if (raw == null) return [];
    try { return (jsonDecode(raw) as List).map((e) => TeacherSchedule.fromJson(Map<String,dynamic>.from(e))).toList(); }
    catch (_) { return []; }
  }
  static Future<void> saveTeachers(List<TeacherSchedule> teachers) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(teachersKey, jsonEncode(teachers.map((e) => e.toJson()).toList()));
  }
  static Future<List<Map<String,dynamic>>> backups() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(backupsKey);
    if (raw == null) return [];
    try { return (jsonDecode(raw) as List).map((e) => Map<String,dynamic>.from(e)).toList(); } catch (_) { return []; }
  }
  static Future<void> backupCurrent() async {
    final teachers = await loadTeachers();
    if (teachers.isEmpty) return;
    final backups = await thisBackups();
    backups.insert(0, {'created': DateTime.now().toIso8601String(), 'teachers': teachers.map((e) => e.toJson()).toList()});
    if (backups.length > 3) backups.removeRange(3, backups.length);
    final p = await SharedPreferences.getInstance();
    await p.setString(backupsKey, jsonEncode(backups));
  }
  static Future<List<Map<String,dynamic>>> thisBackups() => backups();
  static Future<void> restore(int index) async {
    final b = await backups();
    if (index < 0 || index >= b.length) return;
    final teachers = (b[index]['teachers'] as List).map((e) => TeacherSchedule.fromJson(Map<String,dynamic>.from(e))).toList();
    await saveTeachers(teachers);
  }
}


Future<void> _scheduleNotificationsForCurrentData() async {
  final periods = await ScheduleStore.loadPeriods();
  final teachers = await ScheduleStore.loadTeachers();
  final prefs = await SharedPreferences.getInstance();
  final pinned = prefs.getString('pinned_teacher_v1');
  final matches = teachers.where((t) => t.name == pinned).toList();
  final teacher = matches.isNotEmpty ? matches.first :
      (teachers.isNotEmpty ? teachers.first : null);
  await NotificationService.instance.scheduleWeekdayNotifications(
    periods.map((p) => p.toJson()).toList(),
    teacherName: teacher?.name ?? '',
    lessons: teacher?.lessons.map((e) => e.toJson()).toList() ?? const [],
  );
}

class PdfImportResult {
  PdfImportResult(this.teachers, this.warnings);
  final List<TeacherSchedule> teachers;
  final List<String> warnings;
}

/// Reads the school's native XLSX export. It detects teacher blocks by the
/// 'T.C.' marker instead of relying on fixed row numbers or a teacher limit.
class TimetableExcelParser {
  static const _days = <String, String>{
    'Pazartesi': 'Pazartesi', 'Salı': 'Salı', 'Sali': 'Salı',
    'Çarşamba': 'Çarşamba', 'Carsamba': 'Çarşamba',
    'Perşembe': 'Perşembe', 'Persembe': 'Perşembe', 'Cuma': 'Cuma',
  };

  static String _cellText(List<List<Data?>> rows, int row, int col) {
    if (row < 0 || row >= rows.length || col < 0 || col >= rows[row].length) return '';
    final value = rows[row][col]?.value;
    if (value == null) return '';
    // excel 4.x uses typed CellValue objects; their value member contains
    // the primitive text/number for the common cell types.
    try {
      final inner = (value as dynamic).value;
      if (inner != null) return inner.toString().trim();
    } catch (_) {}
    return value.toString().trim();
  }

  static String _key(String value) => value.trim().replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase();

  static Future<PdfImportResult> parse(Uint8List bytes) async {
    final book = Excel.decodeBytes(bytes);
    if (book.tables.isEmpty) throw Exception('Excel dosyasında okunabilir çalışma sayfası bulunamadı.');
    // The school's exported workbook currently has one timetable sheet. If a
    // future export has multiple sheets, scan them all and avoid duplicate
    // teacher records by normalized name.
    final teachers = <TeacherSchedule>[];
    final warnings = <String>[];
    final seen = <String>{};
    for (final sheet in book.tables.values) {
      final rows = sheet.rows;
      final starts = <int>[];
      for (var r = 0; r < rows.length; r++) {
        if (_cellText(rows, r, 0).toUpperCase() == 'T.C.') starts.add(r);
      }
      for (var i = 0; i < starts.length; i++) {
        final start = starts[i];
        final end = i + 1 < starts.length ? starts[i + 1] : rows.length;
        final name = _cellText(rows, start + 5, 2);
        if (name.isEmpty) { warnings.add('${start + 1}. satırdaki öğretmen bloğunda ad bulunamadı.'); continue; }
        // Do not discard homonymous teachers: keep every block and make the
        // visible label unique only when two records have the same name.
        var displayName = name;
        var duplicateNumber = 2;
        while (!seen.add(_key(displayName))) {
          displayName = '$name ($duplicateNumber)';
          duplicateNumber++;
        }
        if (displayName != name) warnings.add('Aynı isimli öğretmen kaydı ayrı tutuldu: $displayName');

        final subjectByCode = <String, String>{};
        // The lesson-detail table begins after the weekly grid. It is used to
        // expand short subject codes into readable subject names.
        for (var r = start + 16; r < end; r++) {
          final code = _cellText(rows, r, 5);
          final subject = _cellText(rows, r, 7);
          if (code.isNotEmpty && subject.isNotEmpty && code != 'Ders Kodu') {
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
            final parts = raw.split(RegExp(r'\r?\n')).map((x) => x.trim()).where((x) => x.isNotEmpty).toList();
            if (parts.length < 2) {
              teacherWarnings.add('$day ${c}. ders hücresi çözümlenemedi.');
              continue;
            }
            final className = parts[0];
            final code = parts[1];
            lessons.add(LessonEntry(day: day, period: c, className: className, code: code, subject: subjectByCode[code] ?? ''));
          }
        }
        final declaredTotal = int.tryParse(_cellText(rows, start + 14, 2));
        if (lessons.isEmpty) teacherWarnings.add('Haftalık ders çizelgesi bulunamadı.');
        if (declaredTotal != null && declaredTotal != lessons.length) {
          teacherWarnings.add('Excel toplamı $declaredTotal saat; çizelgede ${lessons.length} dolu hücre var.');
        }
        teachers.add(TeacherSchedule(name: displayName, lessons: lessons, warning: teacherWarnings.join(' ')));
        warnings.addAll(teacherWarnings.map((w) => '$displayName: $w'));
      }
    }
    if (teachers.isEmpty) throw Exception('Excel içinde T.C. başlığıyla başlayan öğretmen blokları bulunamadı.');
    return PdfImportResult(teachers, warnings);
  }
}

class TimetablePdfParser {
  static final _days = <String, String>{
    'Pazartesi': 'Pazartesi', 'Salı': 'Salı', 'Sali': 'Salı', 'Çarşamba': 'Çarşamba', 'Carsamba': 'Çarşamba',
    'Perşembe': 'Perşembe', 'Persembe': 'Perşembe', 'Cuma': 'Cuma'
  };
  static final _namePattern = RegExp(r'Adı\s*Soyadı\s*:\s*(.+)', caseSensitive: false);
  static final _classPattern = RegExp(r'^\d{1,2}/[A-ZÇĞİÖŞÜ]$');
  static final _codePattern = RegExp(r'^[A-ZÇĞİÖŞÜ]{2,}[0-9A-ZÇĞİÖŞÜ]*$');

  static String _normal(String value) => value.trim().replaceAll(':', '').replaceAll(',', '');

  // Sütunları düz metindeki boşluk sayısına göre değil, PDF kelime koordinatlarına göre
  // eşleştirir. Böylece boş ders hücreleri kaymaya neden olmaz.
  static Future<PdfImportResult> parse(Uint8List bytes) async {
    final doc = PdfDocument(inputBytes: bytes);
    final teachers = <TeacherSchedule>[];
    final warnings = <String>[];
    try {
      final extractor = PdfTextExtractor(doc);
      for (var page = 0; page < doc.pages.count; page++) {
        final pageText = extractor.extractText(startPageIndex: page, endPageIndex: page);
        final nameMatch = _namePattern.firstMatch(pageText);
        if (nameMatch == null) { warnings.add('${page + 1}. sayfada öğretmen adı bulunamadı.'); continue; }
        final name = nameMatch.group(1)!.trim().split(RegExp(r'\s{2,}')).first.trim();
        if (name.isEmpty) { warnings.add('${page + 1}. sayfada öğretmen adı boş.'); continue; }
        final lines = extractor.extractTextLines(startPageIndex: page, endPageIndex: page);
        List<double>? centers;
        for (final line in lines) {
          final found = <int, double>{};
          for (final word in line.wordCollection) {
            final token = _normal(word.text);
            final match = RegExp(r'^\(([1-7])\)$').firstMatch(token);
            if (match != null) found[int.parse(match.group(1)!)] = word.bounds.center.dx;
          }
          if (found.length == 7) {
            centers = List<double>.generate(7, (i) => found[i + 1]!);
            break;
          }
        }
        if (centers == null) {
          warnings.add('$name: 7 ders sütununun başlığı bulunamadı; sayfa kontrol edilmeli.');
          teachers.add(TeacherSchedule(name: name, warning: 'Ders sütunları belirlenemedi.'));
          continue;
        }
        final entries = <LessonEntry>[];
        final teacherWarnings = <String>[];
        for (final dayLine in lines) {
          String? day;
          double? dayY;
          for (final word in dayLine.wordCollection) {
            final token = _normal(word.text);
            if (_days.containsKey(token)) { day = _days[token]; dayY = word.bounds.center.dy; break; }
          }
          if (day == null || dayY == null) continue;
          final codeByColumn = <int, String>{};
          for (final word in dayLine.wordCollection) {
            final token = _normal(word.text);
            if (!_codePattern.hasMatch(token)) continue;
            final col = _nearestColumn(word.bounds.center.dx, centers);
            if (col != null) codeByColumn[col] = token;
          }
          if (codeByColumn.isEmpty) continue;

          Map<int, String>? bestClasses;
          var bestDistance = double.infinity;
          for (final candidate in lines) {
            final y = candidate.bounds.center.dy;
            final distance = dayY - y;
            if (distance <= 0 || distance > 24 || distance >= bestDistance) continue;
            final found = <int, String>{};
            for (final word in candidate.wordCollection) {
              final token = _normal(word.text);
              if (!_classPattern.hasMatch(token)) continue;
              final col = _nearestColumn(word.bounds.center.dx, centers);
              if (col != null) found[col] = token;
            }
            if (found.isNotEmpty) { bestClasses = found; bestDistance = distance; }
          }
          for (final entry in codeByColumn.entries) {
            final className = bestClasses?[entry.key];
            if (className == null) {
              teacherWarnings.add('$day ${entry.key + 1}. ders: sınıf hücresi eşleştirilemedi.');
              continue;
            }
            entries.add(LessonEntry(day: day, period: entry.key + 1, className: className, code: entry.value));
          }
        }
        if (entries.isEmpty) teacherWarnings.add('Ders çizelgesi çözümlenemedi; bu öğretmenin kaydı kontrol edilmeli.');
        teachers.add(TeacherSchedule(name: name, lessons: entries, warning: teacherWarnings.join(' ')));
        warnings.addAll(teacherWarnings.map((w) => '$name: $w'));
      }
    } finally { doc.dispose(); }
    final seen = <String>{};
    final unique = <TeacherSchedule>[];
    for (final t in teachers) {
      final key = t.name.toLocaleLowerCase();
      if (!seen.add(key)) { warnings.add('Tekrarlanan öğretmen kaydı atlandı: ${t.name}'); continue; }
      unique.add(t);
    }
    return PdfImportResult(unique, warnings);
  }

  static int? _nearestColumn(double x, List<double> centers) {
    var index = 0;
    var distance = double.infinity;
    for (var i = 0; i < centers.length; i++) {
      final d = (centers[i] - x).abs();
      if (d < distance) { distance = d; index = i; }
    }
    return distance <= 38 ? index : null;
  }
}

extension _TurkishLower on String {
  String toLocaleLowerCase() => replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase();
}

class KaradagApp extends StatelessWidget {
  const KaradagApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Karadağ Ortaokulu', debugShowCheckedModeBanner: false,
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: brand), useMaterial3: true, scaffoldBackgroundColor: const Color(0xFFF7F9F8)),
    home: const MainShell(),
  );
}

class MainShell extends StatefulWidget { const MainShell({super.key}); @override State<MainShell> createState() => _MainShellState(); }
class _MainShellState extends State<MainShell> {
  int tab = 0;
  List<LessonPeriod> periods = ScheduleStore.defaults();
  List<TeacherSchedule> teachers = [];
  List<Map<String,dynamic>> backups = [];
  bool loading = true;
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    periods = await ScheduleStore.loadPeriods(); teachers = await ScheduleStore.loadTeachers(); backups = await ScheduleStore.backups();
    if (mounted) setState(() => loading = false);
  }
  Future<void> _savePeriods() async {
    await ScheduleStore.savePeriods(periods);
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('notifications_enabled_v1') ?? false) {
      await _scheduleNotificationsForCurrentData();
    }
    if (mounted) setState(() {});
  }
  Future<void> _importSchedule() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx', 'pdf'], withData: true);
    if (result == null || result.files.single.bytes == null) return;
    final file = result.files.single;
    final extension = (file.extension ?? '').toLowerCase();
    setState(() => loading = true);
    try {
      final parsed = extension == 'pdf'
          ? await TimetablePdfParser.parse(file.bytes!)
          : await TimetableExcelParser.parse(file.bytes!);
      if (!mounted) return;
      if (parsed.teachers.isEmpty) throw Exception('Dosyada öğretmen kaydı bulunamadı.');
      final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        title: Text('$extension dosyası önizleme'),
        content: SizedBox(width: 420, child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${parsed.teachers.length} öğretmen kaydı bulundu.'), const SizedBox(height: 8),
          ...parsed.teachers.take(12).map((t) => Text('• ${t.name} — ${t.lessons.length} ders kaydı')),
          if (parsed.teachers.length > 12) Text('… ve ${parsed.teachers.length - 12} öğretmen daha'),
          const SizedBox(height: 8), Text('${parsed.warnings.length} uyarı bulundu.', style: TextStyle(color: parsed.warnings.isEmpty ? Colors.green : Colors.orange)),
          if (parsed.warnings.isNotEmpty) ...[const SizedBox(height: 6), ...parsed.warnings.take(8).map((w) => Text('• $w', style: const TextStyle(fontSize: 12)))],
          const SizedBox(height: 8), const Text('Onaylarsan mevcut program yedeklenecek. Ders saatleri ayarların korunacak.', style: TextStyle(fontSize: 12)),
        ]))),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Programı etkinleştir'))],
      ));
      if (ok == true) {
        await ScheduleStore.backupCurrent();
        await ScheduleStore.saveTeachers(parsed.teachers);
        teachers = parsed.teachers; backups = await ScheduleStore.backups();
        final prefs = await SharedPreferences.getInstance();
        if (prefs.getBool('notifications_enabled_v1') ?? false) {
          await _scheduleNotificationsForCurrentData();
        }
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${teachers.length} öğretmen programı yüklendi.')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Program dosyası okunamadı: $e')));
    } finally { if (mounted) setState(() => loading = false); }
  }
  Future<void> _restore(int i) async { await ScheduleStore.restore(i); teachers = await ScheduleStore.loadTeachers(); final prefs = await SharedPreferences.getInstance(); if (prefs.getBool('notifications_enabled_v1') ?? false) await _scheduleNotificationsForCurrentData(); setState(() {}); }
  @override Widget build(BuildContext context) {
    final pages = [
      HomePage(teachers: teachers, periods: periods),
      PeriodSettingsPage(periods: periods, onChanged: (p) async { periods = p; await _savePeriods(); }),
      ProgramPage(teachers: teachers, backups: backups, onImport: _importSchedule, onRestore: _restore),
      const AboutPage(),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Karadağ Ortaokulu', style: TextStyle(fontWeight: FontWeight.bold)), backgroundColor: brand, foregroundColor: Colors.white),
      body: loading ? const Center(child: CircularProgressIndicator()) : IndexedStack(index: tab, children: pages),
      bottomNavigationBar: NavigationBar(selectedIndex: tab, onDestinationSelected: (v) => setState(() => tab = v), destinations: const [
        NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Ana Sayfa'),
        NavigationDestination(icon: Icon(Icons.schedule_outlined), selectedIcon: Icon(Icons.schedule), label: 'Ders Saatleri'),
        NavigationDestination(icon: Icon(Icons.calendar_month_outlined), selectedIcon: Icon(Icons.calendar_month), label: 'Program'),
        NavigationDestination(icon: Icon(Icons.info_outline), selectedIcon: Icon(Icons.info), label: 'Hakkında'),
      ]),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.teachers, required this.periods});
  final List<TeacherSchedule> teachers; final List<LessonPeriod> periods;
  @override State<HomePage> createState() => _HomePageState();
}
class _HomePageState extends State<HomePage> {
  Timer? timer; DateTime now = DateTime.now(); String? selectedTeacher;
  final TextEditingController teacherSearch = TextEditingController(); String day = weekdays[DateTime.now().weekday - 1 < 5 ? DateTime.now().weekday - 1 : 0];
  @override void initState() { super.initState(); _loadPinnedTeacher(); timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() => now = DateTime.now())); }
  Future<void> _loadPinnedTeacher() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('pinned_teacher_v1');
    if (!mounted || saved == null) return;
    if (widget.teachers.any((t) => t.name == saved)) setState(() => selectedTeacher = saved);
  }
  Future<void> _pinTeacher() async {
    final name = teacher?.name;
    if (name == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pinned_teacher_v1', name);
    if (prefs.getBool('notifications_enabled_v1') ?? false) {
      await _scheduleNotificationsForCurrentData();
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$name sabitlenen öğretmen olarak kaydedildi.')));
  }
  @override void dispose() { timer?.cancel(); teacherSearch.dispose(); super.dispose(); }
  TeacherSchedule? get teacher {
    if (widget.teachers.isEmpty) return null;
    final found = widget.teachers.where((t) => t.name == selectedTeacher).toList();
    return found.isNotEmpty ? found.first : widget.teachers.first;
  }
  int _mins(String value) { final p = value.split(':'); return int.parse(p[0]) * 60 + int.parse(p[1]); }
  String _duration(int seconds) { if (seconds < 0) seconds = 0; final d = Duration(seconds: seconds); return '${d.inHours.toString().padLeft(2,'0')}:${(d.inMinutes%60).toString().padLeft(2,'0')}:${(d.inSeconds%60).toString().padLeft(2,'0')}'; }
  @override Widget build(BuildContext context) {
    final dayLessons = teacher?.lessons.where((e) => e.day == day).toList() ?? [];
    final minute = now.hour * 60 + now.minute;
    LessonPeriod? active; LessonPeriod? next;
    for (final p in widget.periods) { if (minute >= _mins(p.start) && minute < _mins(p.end)) active = p; if (_mins(p.start) > minute && next == null) next = p; }
    final countdown = active != null ? (_mins(active.end) * 60 - now.hour * 3600 - now.minute * 60 - now.second) : next != null ? (_mins(next.start) * 60 - now.hour * 3600 - now.minute * 60 - now.second) : null;
    final title = active != null ? 'Teneffüse kalan süre' : next != null ? 'Bir sonraki derse kalan süre' : 'Bugünkü dersler tamamlandı';
    final todayIsWeekday = now.weekday >= 1 && now.weekday <= 5;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [const Expanded(child: Text('Günlük ders programı', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))), Chip(label: Text(DateFormat('dd.MM.yyyy').format(now)))]),
      const SizedBox(height: 12),
      if (widget.teachers.isNotEmpty) ...[
      TextField(controller: teacherSearch, decoration: InputDecoration(labelText: 'Öğretmen ara', hintText: 'Ad veya soyad yazın', prefixIcon: const Icon(Icons.search), suffixIcon: teacherSearch.text.isEmpty ? null : IconButton(icon: const Icon(Icons.close), onPressed: () { teacherSearch.clear(); setState(() {}); }), border: const OutlineInputBorder()), onChanged: (_) => setState(() {})),
      const SizedBox(height: 8),
      Builder(builder: (context) {
        final q = teacherSearch.text.trim().replaceAll('İ','i').replaceAll('I','ı').toLowerCase();
        final matches = widget.teachers.where((t) => t.name.replaceAll('İ','i').replaceAll('I','ı').toLowerCase().contains(q)).toList();
        final selected = matches.any((t) => t.name == teacher?.name) ? teacher?.name : (matches.isNotEmpty ? matches.first.name : null);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DropdownButtonFormField<String>(value: selected, isExpanded: true, decoration: const InputDecoration(labelText: 'Öğretmen seçimi', border: OutlineInputBorder()), items: matches.map((t) => DropdownMenuItem(value: t.name, child: Text(t.name, overflow: TextOverflow.ellipsis))).toList(), onChanged: matches.isEmpty ? null : (v) => setState(() => selectedTeacher = v)),
          Align(alignment: Alignment.centerRight, child: TextButton.icon(onPressed: teacher == null ? null : _pinTeacher, icon: const Icon(Icons.push_pin_outlined), label: const Text('Öğretmenimi sabitle'))),
        ]);
      }),
    ],
      if (widget.teachers.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('Henüz program yüklenmedi. Program sekmesinden Excel veya PDF ekleyebilirsin.'))),
      const SizedBox(height: 12),
      Wrap(spacing: 6, children: weekdays.map((d) => ChoiceChip(label: Text(d.substring(0,3)), selected: day == d, onSelected: (_) => setState(() => day = d))).toList()),
      const SizedBox(height: 12),
      Card(color: active != null ? const Color(0xFFE2F4E8) : null, child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w600)), const SizedBox(height: 6),
        Text(countdown == null || !todayIsWeekday ? '--:--:--' : _duration(countdown), style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: active != null ? brand : null)),
        Text(active != null ? '${active.number}. ders ${active.start}–${active.end}' : next != null ? '${next.number}. ders ${next.start}’de başlayacak' : 'Ders saati dışında', style: const TextStyle(color: Colors.black54)),
      ]))),
      const SizedBox(height: 12), const Text('Ders çizelgesi', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      if (!todayIsWeekday) const Padding(padding: EdgeInsets.all(16), child: Text('Hafta sonu için ders programı bulunmuyor.')),
      ...widget.periods.map((p) {
        final entry = dayLessons.where((e) => e.period == p.number).toList();
        final isActive = todayIsWeekday && day == weekdays[now.weekday - 1] && minute >= _mins(p.start) && minute < _mins(p.end);
        return Card(color: isActive ? const Color(0xFFDDF2E3) : null, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: isActive ? const BorderSide(color: brand, width: 2) : BorderSide.none), child: ListTile(
          leading: CircleAvatar(backgroundColor: isActive ? brand : null, foregroundColor: isActive ? Colors.white : null, child: Text('${p.number}')),
          title: Text(entry.isEmpty ? 'Boş ders saati' : entry.map((e) => e.subject.isNotEmpty ? e.subject : e.code).join(' / '), style: TextStyle(fontWeight: isActive ? FontWeight.bold : FontWeight.w500)),
          subtitle: Text(entry.isEmpty ? 'Ders bulunmuyor' : entry.map((e) => '${e.className} · ${e.code}').join('  |  ')),
          trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [Text('${p.start}–${p.end}', style: const TextStyle(fontSize: 12)), if (isActive) const Text('ŞU AN', style: TextStyle(color: brand, fontWeight: FontWeight.bold, fontSize: 11))]),
        ));
      }),
      if (teacher?.warning.isNotEmpty == true) Padding(padding: const EdgeInsets.all(8), child: Text('Program kontrol uyarısı: ${teacher!.warning}', style: const TextStyle(color: Colors.deepOrange))),
    ]);
  }
}

class PeriodSettingsPage extends StatelessWidget {
  const PeriodSettingsPage({super.key, required this.periods, required this.onChanged});
  final List<LessonPeriod> periods; final ValueChanged<List<LessonPeriod>> onChanged;
  Future<void> _edit(BuildContext context, LessonPeriod p) async {
    final s = TextEditingController(text: p.start); final e = TextEditingController(text: p.end);
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: Text('${p.number}. ders saatini düzenle'), content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: s, decoration: const InputDecoration(labelText: 'Başlangıç (SS:DD)')), TextField(controller: e, decoration: const InputDecoration(labelText: 'Bitiş (SS:DD)'))]), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Kaydet'))]));
    if (ok == true && _valid(s.text) && _valid(e.text) && _minutes(s.text) < _minutes(e.text)) { final updated = periods.map((x) => x.number == p.number ? LessonPeriod(number: x.number, start: s.text, end: e.text) : x).toList(); onChanged(updated); }
  }
  bool _valid(String s) => RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(s);
  int _minutes(String s) { final a=s.split(':'); return int.parse(a[0])*60+int.parse(a[1]); }
  @override Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
    const Text('Ders saatleri', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)), const Text('Bu saatler hafta içi bütün günler ve öğretmenler için ortak varsayılandır.'), const SizedBox(height: 12),
    ...periods.map((p) => Card(child: ListTile(leading: CircleAvatar(child: Text('${p.number}')), title: Text('${p.start} – ${p.end}'), subtitle: Text('${p.number}. ders'), trailing: IconButton(icon: const Icon(Icons.edit), onPressed: () => _edit(context,p))))),
    OutlinedButton.icon(onPressed: () => onChanged(ScheduleStore.defaults()), icon: const Icon(Icons.restore), label: const Text('Varsayılan saatleri geri yükle')),
    const SizedBox(height: 8), const Text('Not: Bu sürümde 7 varsayılan ders saati düzenlenebilir. Ders ekleme/kaldırma ve özel gün istisnaları sonraki geliştirme adımında tamamlanacak.', style: TextStyle(color: Colors.black54, fontSize: 12)),
  ]);
}

class ProgramPage extends StatelessWidget {
  const ProgramPage({super.key, required this.teachers, required this.backups, required this.onImport, required this.onRestore});
  final List<TeacherSchedule> teachers; final List<Map<String,dynamic>> backups; final VoidCallback onImport; final ValueChanged<int> onRestore;
  @override Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
    const Text('Program yönetimi', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)), const SizedBox(height: 12),
    Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [const Icon(Icons.table_view, size: 44, color: brand), const SizedBox(height: 8), const Text('Yeni ders programı ekle', style: TextStyle(fontWeight: FontWeight.bold)), const Text('Excel (.xlsx) veya PDF dosyası seçilir. Öğretmen sayısı için sabit bir üst sınır yoktur; bulunan tüm kayıtlar önizlenir.', textAlign: TextAlign.center), const SizedBox(height: 12), FilledButton.icon(onPressed: onImport, icon: const Icon(Icons.upload_file), label: const Text('Excel / PDF dosyası seç'))]))),
    Card(child: ListTile(leading: const Icon(Icons.people_alt_outlined), title: const Text('Aktif öğretmen sayısı'), trailing: Text('${teachers.length}'))),
    const SizedBox(height: 12), const Text('Son üç program yedeği', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
    if (backups.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('Henüz yedek bulunmuyor. Yeni program yüklenirken mevcut program otomatik yedeklenecek.'))),
    ...backups.asMap().entries.map((entry) { final b=entry.value; final date=DateTime.tryParse(b['created'] ?? '') ; final count=(b['teachers'] as List?)?.length ?? 0; return Card(child: ListTile(leading: const Icon(Icons.backup), title: Text('Program yedeği ${entry.key+1}'), subtitle: Text('${date == null ? 'Tarih yok' : DateFormat('dd.MM.yyyy HH:mm').format(date)} · $count öğretmen'), trailing: TextButton(onPressed: () async { final yes=await showDialog<bool>(context: context,builder:(ctx)=>AlertDialog(title: const Text('Yedek geri yüklensin mi?'),content: const Text('Mevcut programın üzerine yazılacak.'),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Vazgeç')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Geri yükle'))])); if(yes==true) onRestore(entry.key); }, child: const Text('Geri yükle')))); }),
    const SizedBox(height: 8), const Text('Excel/PDF içe aktarma ve yedekleme cihaz üzerinde, internet bağlantısı olmadan yapılacak şekilde tasarlanmıştır.', style: TextStyle(fontSize: 12, color: Colors.black54)),
  ]);
}

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});
  @override State<AboutPage> createState() => _AboutPageState();
}
class _AboutPageState extends State<AboutPage> {
  static const _notificationsKey = 'notifications_enabled_v1';
  bool notificationsEnabled = false;
  bool loaded = false;
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final savedNotificationSetting = prefs.getBool(_notificationsKey) ?? false;
    if (savedNotificationSetting) {
      await _scheduleNotificationsForCurrentData();
    }
    if (!mounted) return;
    setState(() { notificationsEnabled = savedNotificationSetting; loaded = true; });
  }
  Future<void> _setOption(String key, bool value, bool isNotification) async {
    final prefs = await SharedPreferences.getInstance();
    if (isNotification) {
      if (value) {
        final granted = await NotificationService.instance.requestPermission();
        if (!granted) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Bildirim izni verilmedi. Telefon ayarlarından izin verebilirsiniz.')),
          );
          return;
        }
        await _scheduleNotificationsForCurrentData();
      } else {
        await NotificationService.instance.cancelAll();
      }
    }
    await prefs.setBool(key, value);
    if (!mounted) return;
    setState(() { notificationsEnabled = value; });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
      isNotification
          ? (value ? 'Ders ve teneffüs bildirimleri etkinleştirildi.' : 'Bildirimler kapatıldı.')
          : 'Tercihiniz kaydedildi.',
    )));
  }
  @override Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(20), children: [
    const Center(child: Column(children: [CircleAvatar(radius: 34, backgroundColor: brand, child: Icon(Icons.school, color: Colors.white, size: 36)), SizedBox(height: 12), Text('Karadağ Ortaokulu', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)), SizedBox(height: 4), Text('Ders Programı Uygulaması', style: TextStyle(color: Colors.black54))])),
    const SizedBox(height: 24),
    Card(child: Column(children: [
      SwitchListTile(value: notificationsEnabled, onChanged: loaded ? (v) => _setOption(_notificationsKey, v, true) : null, secondary: const Icon(Icons.notifications_active_outlined), title: const Text('Ders ve teneffüs bildirimleri'), subtitle: const Text('Ders ve teneffüs uyarıları ile ilk dersten 30 dakika önce başlayıp son dersten 10 dakika sonra kapanan kalıcı motivasyon bildirimi.'),),
    ])),
    const Padding(padding: EdgeInsets.only(top: 8), child: Text('Bu seçenekler kullanıcı onayıyla etkinleştirilir. Android cihaz izinleri ayrıca istenebilir.', style: TextStyle(fontSize: 12, color: Colors.black54))),
    const SizedBox(height: 24),
    const Text('Bu uygulama Karadağ Bilgisayar ve Öğretim Teknolojileri Zümreleri tarafından hazırlanmıştır.\n\nHasari Kaşkan, Hakan Aldağ, Hüseyin Yapıcı', textAlign: TextAlign.center, style: TextStyle(height: 1.6)),
  ]);
}
