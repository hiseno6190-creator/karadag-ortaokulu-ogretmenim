
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PersonalAreaPage extends StatefulWidget {
  const PersonalAreaPage({super.key});

  @override
  State<PersonalAreaPage> createState() => _PersonalAreaPageState();
}

class _PersonalAreaPageState extends State<PersonalAreaPage> {
  static const Color brand = Color(0xFF1565C0);
  static const String notesKey = 'personal_notes_v1';
  static const String filesKey = 'personal_files_v1';

  List<Map<String, dynamic>> notes = [];
  List<Map<String, dynamic>> documents = [];

  bool loading = true;
  String searchText = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();

    final savedNotes = prefs.getString(notesKey);
    final savedFiles = prefs.getString(filesKey);

    if (!mounted) return;

    setState(() {
      if (savedNotes != null) {
        notes = List<Map<String, dynamic>>.from(
          (jsonDecode(savedNotes) as List).map(
            (item) => Map<String, dynamic>.from(item),
          ),
        );
      }

      if (savedFiles != null) {
        documents = List<Map<String, dynamic>>.from(
          (jsonDecode(savedFiles) as List).map(
            (item) => Map<String, dynamic>.from(item),
          ),
        );
      }

      loading = false;
    });
  }

  Future<void> _saveNotes() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(notesKey, jsonEncode(notes));
  }

  Future<void> _saveFiles() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(filesKey, jsonEncode(documents));
  }

  Future<void> _editNote({Map<String, dynamic>? note, int? index}) async {
    final titleController = TextEditingController(
      text: note?['title'] ?? '',
    );
    final contentController = TextEditingController(
      text: note?['content'] ?? '',
    );

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(note == null ? 'Yeni Not' : 'Notu Düzenle'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(
                  labelText: 'Not başlığı',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: contentController,
                minLines: 4,
                maxLines: 8,
                decoration: const InputDecoration(
                  labelText: 'Not içeriği',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () {
              if (titleController.text.trim().isEmpty &&
                  contentController.text.trim().isEmpty) {
                return;
              }
              Navigator.pop(dialogContext, true);
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );

    if (result == true) {
      final now = DateTime.now().toIso8601String();

      final newNote = <String, dynamic>{
        'title': titleController.text.trim().isEmpty
            ? 'Başlıksız Not'
            : titleController.text.trim(),
        'content': contentController.text.trim(),
        'date': now,
      };

      setState(() {
        if (index != null) {
          notes[index] = newNote;
        } else {
          notes.insert(0, newNote);
        }
      });

      await _saveNotes();
    }

    titleController.dispose();
    contentController.dispose();
  }

  Future<void> _deleteNote(int index) async {
    final confirmed = await _confirmDelete('Bu not silinsin mi?');
    if (!confirmed) return;

    setState(() => notes.removeAt(index));
    await _saveNotes();
  }

  Future<bool> _confirmDelete(String message) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Silme Onayı'),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Vazgeç'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Sil'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _addFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx', 'xls', 'xlsx'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final pickedFile = result.files.first;
      final bytes = pickedFile.bytes;

      if (bytes == null) {
        _showMessage('Dosya okunamadı. Lütfen tekrar deneyin.');
        return;
      }

      final directory = await getApplicationDocumentsDirectory();
      final folder = Directory('${directory.path}/personal_files');

      if (!await folder.exists()) {
        await folder.create(recursive: true);
      }

      final safeName =
          '${DateTime.now().millisecondsSinceEpoch}_${pickedFile.name}';
      final savedPath = '${folder.path}/$safeName';

      await File(savedPath).writeAsBytes(bytes);

      setState(() {
        documents.insert(0, {
          'name': pickedFile.name,
          'path': savedPath,
          'extension': pickedFile.extension ?? '',
          'date': DateTime.now().toIso8601String(),
          'size': bytes.length,
        });
      });

      await _saveFiles();
      _showMessage('Dosya başarıyla eklendi.');
    } catch (e) {
      _showMessage('Dosya eklenirken bir hata oluştu.');
    }
  }

  Future<void> _deleteFile(int index) async {
    final confirmed = await _confirmDelete(
      'Bu dosya uygulamadan silinsin mi?',
    );

    if (!confirmed) return;

    final path = documents[index]['path'] as String?;

    if (path != null) {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    }

    setState(() => documents.removeAt(index));
    await _saveFiles();
    _showMessage('Dosya silindi.');
  }

  void _showFileInfo(Map<String, dynamic> document) {
    final size = document['size'] as int? ?? 0;
    final sizeText = size < 1024
        ? '$size bayt'
        : '${(size / 1024).toStringAsFixed(1)} KB';

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(document['name'] ?? 'Dosya'),
        content: Text(
          'Dosya türü: ${(document['extension'] ?? '').toString().toUpperCase()}\n'
          'Boyut: $sizeText\n\n'
          'Dosya uygulama içinde saklanmaktadır. Açma ve paylaşma işlemleri sonraki sürümde eklenecektir.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Kapat'),
          ),
        ],
      ),
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _formatDate(dynamic value) {
    if (value == null) return '';
    final date = DateTime.tryParse(value.toString());
    if (date == null) return '';
    return '${date.day.toString().padLeft(2, '0')}.'
        '${date.month.toString().padLeft(2, '0')}.'
        '${date.year}';
  }

  IconData _fileIcon(String extension) {
    switch (extension.toLowerCase()) {
      case 'pdf':
        return Icons.picture_as_pdf_outlined;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart_outlined;
      case 'doc':
      case 'docx':
        return Icons.description_outlined;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }

  Widget _sectionTitle(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 10),
      child: Row(
        children: [
          Icon(icon, color: brand),
          const SizedBox(width: 9),
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _notesSection() {
    final filteredNotes = notes.where((note) {
      final query = searchText.toLowerCase();
      return (note['title'] ?? '').toString().toLowerCase().contains(query) ||
          (note['content'] ?? '').toString().toLowerCase().contains(query);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Notlarım', Icons.sticky_note_2_outlined),
        TextField(
          onChanged: (value) => setState(() => searchText = value),
          decoration: InputDecoration(
            hintText: 'Notlarımda ara...',
            prefixIcon: const Icon(Icons.search),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
        const SizedBox(height: 10),
        if (filteredNotes.isEmpty)
          _emptyCard(
            Icons.note_add_outlined,
            searchText.isEmpty
                ? 'Henüz not eklemediniz.'
                : 'Aramanızla eşleşen not bulunamadı.',
          )
        else
          ...filteredNotes.map((note) {
            final index = notes.indexOf(note);
            return Card(
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 9),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFE3F2FD),
                  child: Icon(Icons.note_alt_outlined, color: brand),
                ),
                title: Text(
                  note['title'] ?? 'Başlıksız Not',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  '${note['content'] ?? ''}\n${_formatDate(note['date'])}',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                isThreeLine: true,
                trailing: PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'edit') {
                      _editNote(note: note, index: index);
                    } else if (value == 'delete') {
                      _deleteNote(index);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'edit',
                      child: Text('Düzenle'),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text('Sil'),
                    ),
                  ],
                ),
                onTap: () => _editNote(note: note, index: index),
              ),
            );
          }),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _editNote(),
            icon: const Icon(Icons.add),
            label: const Text('Yeni Not Ekle'),
          ),
        ),
      ],
    );
  }

  Widget _filesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Dosyalarım', Icons.folder_open_outlined),
        const Text(
          'Excel, Word ve PDF belgelerinizi telefonunuzdan ekleyebilirsiniz.',
          style: TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 10),
        if (documents.isEmpty)
          _emptyCard(
            Icons.folder_open,
            'Henüz dosya eklemediniz.',
          )
        else
          ...documents.asMap().entries.map((entry) {
            final index = entry.key;
            final document = entry.value;

            return Card(
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFFE3F2FD),
                  child: Icon(
                    _fileIcon(document['extension'] ?? ''),
                    color: brand,
                  ),
                ),
                title: Text(
                  document['name'] ?? 'Dosya',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(_formatDate(document['date'])),
                onTap: () => _showFileInfo(document),
                trailing: PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'delete') _deleteFile(index);
                    if (value == 'info') _showFileInfo(document);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'info',
                      child: Text('Dosya bilgisi'),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text('Sil'),
                    ),
                  ],
                ),
              ),
            );
          }),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _addFile,
            icon: const Icon(Icons.upload_file),
            label: const Text('Telefondan Dosya Ekle'),
          ),
        ),
      ],
    );
  }

  Widget _emptyCard(IconData icon, String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F8FC),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Icon(icon, size: 32, color: Colors.blueGrey),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black54),
          ),
        ],
      ),
    );
  }

  Widget _aboutSection() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 22, bottom: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF3FF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD2E3F8)),
      ),
      child: Column(
        children: [
          const CircleAvatar(
            radius: 30,
            backgroundColor: brand,
            child: Icon(
              Icons.school_outlined,
              color: Colors.white,
              size: 32,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Karadağ Ortaokulu',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.bold,
              color: brand,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Öğretmenim',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Text(
            'Ders Programı ve Bildirim Uygulaması',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54),
          ),
          const Divider(height: 28),
          const Text(
            'HAZIRLAYAN',
            style: TextStyle(
              fontSize: 12,
              letterSpacing: 1.5,
              fontWeight: FontWeight.bold,
              color: brand,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Karadağ Ortaokulu',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 5),
          const Text(
            'Bilgisayar ve Öğretim Teknolojileri Zümre Öğretmenleri',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 14),
          const Text('Hasari Kaşkan'),
          const Text('Hakan Aldağ'),
          const Text('Hüseyin Yapıcı'),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFD),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
          children: [
            const Text(
              'Kişisel Alan',
              style: TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.bold,
                color: brand,
              ),
            ),
            const SizedBox(height: 5),
            const Text(
              'Notlarınızı ve belgelerinizi tek yerde saklayın.',
              style: TextStyle(color: Colors.black54),
            ),
            _notesSection(),
            _filesSection(),
            _aboutSection(),
          ],
        ),
      ),
    );
  }
}

