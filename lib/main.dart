import 'dart:async';
import 'dart:convert';

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
    text: 'print("Привет из PipisTerminal!")\n',
  );
  final _scrollController = ScrollController();

  Timer? _statusTimer;
  bool _pythonReady = false;
  bool _running = false;
  String _output = 'PipisTerminal\nГотовлю Python...';

  Uri get _runUri => Uri.parse('http://127.0.0.1:$_pythonPort/run');
  Uri get _healthUri => Uri.parse('http://127.0.0.1:$_pythonPort/health');

  @override
  void initState() {
    super.initState();
    _startPython();
  }

  void _startPython() {
    try {
      SeriousPython.run();
    } catch (error) {
      setState(() {
        _output = 'Не удалось запустить Python:\n$error';
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
            _output = 'Python 3\nГотов к запуску.';
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
      _output = 'Запуск...';
    });

    try {
      final response = await http
          .post(
            _runUri,
            headers: {'content-type': 'application/json'},
            body: jsonEncode({'code': _controller.text}),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        setState(() {
          _output = 'Python server error ${response.statusCode}\n${response.body}';
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
        parts.add('\nExit code: $exitCode');
      }

      setState(() {
        _output = parts.join('\n');
      });
    } catch (error) {
      setState(() {
        _output = 'Ошибка запуска:\n$error';
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
      _output = _pythonReady ? 'Python 3\nГотов к запуску.' : 'Готовлю Python...';
    });
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF15121A),
        title: const Text('PipisTerminal'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
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
            Expanded(
              flex: 6,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
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
