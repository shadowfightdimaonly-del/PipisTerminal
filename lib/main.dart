import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:serious_python/serious_python.dart';

const _pythonPort = 8765;
const _purple = Color(0xFF9C4DFF);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PipisTerminalApp());
}

class PipisTerminalApp extends StatelessWidget {
  const PipisTerminalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'PipisTerminal',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        colorScheme: const ColorScheme.dark(
          primary: _purple,
          secondary: _purple,
          surface: Color(0xFF15121A),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF15121A),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      home: const TerminalScreen(),
    );
  }
}

class TerminalScreen extends StatefulWidget {
  const TerminalScreen({super.key});

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  final _controller = TextEditingController(
    text: 'print("Привет из PipisTerminal!")\\n',
  );
  final _argsController = TextEditingController();
  final _scrollController = ScrollController();

  Timer? _statusTimer;
  bool _pythonReady = false;
  bool _running = false;
  bool _dirty = false;
  String? _filePath;
  String? _workingDirectory;
  String _output = 'PipisTerminal\\nГотовлю Python...';

  Uri get _runUri => Uri.parse('http://127.0.0.1:$_pythonPort/run');
  Uri get _healthUri => Uri.parse('http://127.0.0.1:$_pythonPort/health');

  String get _fileName => _filePath == null
      ? 'Новый файл'
      : _filePath!.split(Platform.pathSeparator).last;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_markDirty);
    _startPython();
  }

  void _markDirty() {
    if (mounted && !_dirty) {
      setState(() {
        _dirty = true;
      });
    }
  }

  Future<void> _openFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['py'],
      );
      if (result == null || result.files.single.path == null) return;

      final path = result.files.single.path!;
      final content = await File(path).readAsString();

      _controller.removeListener(_markDirty);
      _controller.text = content;
      _controller.selection = TextSelection.collapsed(offset: content.length);
      _controller.addListener(_markDirty);

      if (mounted) {
        setState(() {
          _filePath = path;
          _workingDirectory = File(path).parent.path;
          _dirty = false;
          _output = 'Открыт файл:\\n$_fileName';
        });
      }
    } catch (error) {
      _showMessage('Не удалось открыть файл:\\n$error');
    }
  }

  Future<void> _chooseWorkingDirectory() async {
    try {
      final path = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Выбрать рабочую папку проекта',
      );
      if (path == null || !mounted) return;

      setState(() {
        _workingDirectory = path;
        _output = 'Рабочая папка:\\n$path';
      });
    } catch (error) {
      _showMessage('Не удалось выбрать папку:\\n$error');
    }
  }

  Future<void> _saveFile() async {
    if (_filePath == null) {
      await _saveAs();
      return;
    }

    try {
      await File(_filePath!).writeAsString(_controller.text);
      if (mounted) {
        setState(() {
          _dirty = false;
          _output = 'Сохранено:\\n$_fileName';
        });
      }
    } catch (error) {
      _showMessage('Не удалось сохранить файл:\\n$error');
    }
  }

  Future<void> _saveAs() async {
    try {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Сохранить Python-файл',
        fileName: _filePath == null ? 'main.py' : _fileName,
        type: FileType.custom,
        allowedExtensions: ['py'],
      );
      if (path == null) return;

      await File(path).writeAsString(_controller.text);
      if (mounted) {
        setState(() {
          _filePath = path;
          _workingDirectory = File(path).parent.path;
          _dirty = false;
          _output = 'Сохранено как:\\n$_fileName';
        });
      }
    } catch (error) {
      _showMessage('Не удалось сохранить файл:\\n$error');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _startPython() {
    try {
      SeriousPython.run();
    } catch (error) {
      setState(() {
        _output = 'Не удалось запустить Python:\\n$error';
      });
      return;
    }

    _statusTimer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      _checkPython();
    });
    _checkPython();
  }

  Future<void> _checkPython() async {
    try {
      final response = await http
          .get(_healthUri)
          .timeout(const Duration(milliseconds: 500));
      if (response.statusCode == 200 && mounted) {
        if (!_pythonReady) {
          setState(() {
            _pythonReady = true;
            _output = 'Python 3\\nГотов к запуску.';
          });
        }
        _statusTimer?.cancel();
      }
    } catch (_) {
      // Python is still starting. Keep polling.
    }
  }

  Future<void> _runCode() async {
    if (_running || !_pythonReady) return;

    setState(() {
      _running = true;
      _output = 'Запуск $_fileName...';
    });

    try {
      final response = await http
          .post(
            _runUri,
            headers: {'content-type': 'application/json'},
            body: jsonEncode({
              'code': _controller.text,
              'fileName': _filePath ?? '<PipisTerminal>',
              'args': _argsController.text,
              'cwd': _workingDirectory,
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        setState(() {
          _output = 'Python server error ${response.statusCode}\\n${response.body}';
        });
        return;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final stdout = (data['stdout'] ?? '').toString();
      final stderr = (data['stderr'] ?? '').toString();
      final exitCode = data['exitCode'];

      final parts = <String>[];
      if (stdout.isNotEmpty) parts.add(stdout.trimRight());
      if (stderr.isNotEmpty) parts.add(stderr.trimRight());
      if (parts.isEmpty) parts.add('[Program finished]');
      if (exitCode != null && exitCode != 0) {
        parts.add('\\nExit code: $exitCode');
      }

      setState(() {
        _output = parts.join('\\n');
      });
    } catch (error) {
      setState(() {
        _output = 'Ошибка запуска:\\n$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _running = false;
        });
      }
    }
  }

  void _clearOutput() {
    setState(() {
      _output = _pythonReady ? 'Python 3\\nГотов к запуску.' : 'Готовлю Python...';
    });
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _controller.removeListener(_markDirty);
    _controller.dispose();
    _argsController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF15121A),
        titleSpacing: 12,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('PipisTerminal'),
            Text(
              '${_dirty ? '● ' : ''}$_fileName',
              style: const TextStyle(fontSize: 12, color: Colors.white70),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Открыть .py',
            onPressed: _openFile,
            icon: const Icon(Icons.folder_open),
          ),
          IconButton(
            tooltip: 'Рабочая папка проекта',
            onPressed: _chooseWorkingDirectory,
            icon: const Icon(Icons.folder_copy_outlined),
          ),
          IconButton(
            tooltip: 'Сохранить',
            onPressed: _saveFile,
            icon: const Icon(Icons.save),
          ),
          IconButton(
            tooltip: 'Сохранить как',
            onPressed: _saveAs,
            icon: const Icon(Icons.save_as),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Center(
              child: Row(
                children: [
                  Icon(
                    Icons.circle,
                    size: 10,
                    color: _pythonReady ? Colors.greenAccent : Colors.orangeAccent,
                  ),
                  const SizedBox(width: 7),
                  Text(_pythonReady ? 'Python' : 'Запуск'),
                ],
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
              child: TextField(
                controller: _argsController,
                maxLines: 1,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'Аргументы командной строки',
                  hintText: 'например: hello "hello world"',
                  helperText: _workingDirectory == null
                      ? 'Рабочая папка не выбрана'
                      : 'Папка: $_workingDirectory',
                  helperMaxLines: 1,
                  prefixIcon: const Icon(Icons.terminal),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 6,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                child: TextField(
                  controller: _controller,
                  expands: true,
                  maxLines: null,
                  minLines: null,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 15,
                    height: 1.35,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Напиши Python-код...',
                    alignLabelWithHint: true,
                    contentPadding: EdgeInsets.all(14),
                  ),
                  textAlignVertical: TextAlignVertical.top,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _pythonReady && !_running ? _runCode : null,
                      icon: Icon(_running ? Icons.hourglass_top : Icons.play_arrow),
                      label: Text(_running ? 'Запуск...' : 'Запустить'),
                      style: FilledButton.styleFrom(
                        backgroundColor: _purple,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Очистить вывод',
                    onPressed: _clearOutput,
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 4,
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF090909),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF2B2235)),
                ),
                child: SingleChildScrollView(
                  controller: _scrollController,
                  child: SelectableText(
                    _output,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 14,
                      height: 1.35,
                      color: Color(0xFFE8E8E8),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
