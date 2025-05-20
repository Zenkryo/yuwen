import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:math';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '词语学习',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const WordDisplayPage(),
    );
  }
}

class WordDisplayPage extends StatefulWidget {
  const WordDisplayPage({super.key});

  @override
  State<WordDisplayPage> createState() => _WordDisplayPageState();
}

class _WordDisplayPageState extends State<WordDisplayPage> {
  Map<String, dynamic>? _words;
  String? _currentWord;
  bool _showPinyin = false;
  bool _showExplanation = false;
  final Random _random = Random();
  final FocusNode _focusNode = FocusNode();
  final List<String> _history = [];
  int _currentIndex = -1;
  String? _currentFrom;
  List<String> _fromList = [];

  @override
  void initState() {
    super.initState();
    _loadWords();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadWords() async {
    try {
      final String jsonString = await rootBundle.loadString(
        'resources/all_words.json',
      );
      setState(() {
        _words = json.decode(jsonString);
        // 从所有词语中提取唯一的来源
        _fromList =
            _words!.values
                .map((word) => word['from'] as String)
                .toSet()
                .toList()
              ..sort(); // 按字母顺序排序
        _currentFrom = _fromList.last; // 默认选择最后一个来源
        _selectRandomWord();
      });
    } catch (e) {
      debugPrint('加载词语文件失败: $e');
    }
  }

  void _changeFrom(int direction) {
    if (_fromList.isEmpty) return;
    final currentIndex = _fromList.indexOf(_currentFrom!);
    final newIndex =
        (currentIndex + direction + _fromList.length) % _fromList.length;
    setState(() {
      _currentFrom = _fromList[newIndex];
      _selectRandomWord();
    });
  }

  void _selectRandomWord() {
    if (_words == null || _words!.isEmpty || _currentFrom == null) return;

    // 筛选出当前来源的词语
    final filteredWords =
        _words!.entries
            .where((entry) => entry.value['from'] == _currentFrom)
            .map((entry) => entry.key)
            .toList();

    if (filteredWords.isEmpty) return;

    final newWord = filteredWords[_random.nextInt(filteredWords.length)];

    // 如果当前有词语，将其添加到历史记录
    if (_currentWord != null) {
      if (_currentIndex < _history.length - 1) {
        _history.removeRange(_currentIndex + 1, _history.length);
      }
      _history.add(_currentWord!);
      _currentIndex = _history.length - 1;
    }

    setState(() {
      _currentWord = newWord;
      _showPinyin = false;
      _showExplanation = false;
    });
  }

  void _navigateHistory(int direction) {
    if (_history.isEmpty) return;

    final newIndex = _currentIndex + direction;
    if (newIndex >= 0 && newIndex < _history.length) {
      setState(() {
        _currentWord = _history[newIndex];
        _currentIndex = newIndex;
        _showPinyin = false;
        _showExplanation = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GestureDetector(
        onTap: () {
          _focusNode.requestFocus();
        },
        child: KeyboardListener(
          focusNode: _focusNode,
          autofocus: true,
          onKeyEvent: (KeyEvent event) {
            if (event is KeyDownEvent) {
              if (event.logicalKey == LogicalKeyboardKey.space) {
                _selectRandomWord();
              } else if (event.logicalKey == LogicalKeyboardKey.keyP) {
                setState(() {
                  _showPinyin = !_showPinyin;
                });
              } else if (event.logicalKey == LogicalKeyboardKey.keyX) {
                setState(() {
                  _showExplanation = !_showExplanation;
                });
              } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                _navigateHistory(-1);
              } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                _navigateHistory(1);
              } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                _changeFrom(-1);
              } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                _changeFrom(1);
              }
            }
          },
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_currentWord != null) ...[
                  SizedBox(
                    height: 80,
                    child: Center(
                      child: Text(
                        _currentWord!,
                        style: const TextStyle(
                          fontSize: 48,
                          fontFamily: 'STKaiti',
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 60,
                    child: Center(
                      child:
                          _showPinyin && _words != null
                              ? Text(
                                _words![_currentWord]!['pinyin'].join(' '),
                                style: const TextStyle(
                                  fontSize: 28,
                                  color: Colors.grey,
                                  fontFamily: 'Monaco',
                                  letterSpacing: 1,
                                ),
                              )
                              : null,
                    ),
                  ),
                  SizedBox(
                    height: 100,
                    child: Center(
                      child:
                          _showExplanation && _words != null
                              ? Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 40,
                                ),
                                child: Text(
                                  _words![_currentWord]!['explanation'],
                                  style: const TextStyle(
                                    fontSize: 20,
                                    color: Colors.black87,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              )
                              : null,
                    ),
                  ),
                ] else
                  const CircularProgressIndicator(),
                const SizedBox(height: 40),
                Text(
                  _currentFrom!,
                  style: const TextStyle(
                    fontSize: 18,
                    color: Colors.blue,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          border: Border(top: BorderSide(color: Colors.grey[300]!, width: 1)),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Text('空格键：切换词语', style: TextStyle(color: Colors.grey)),
            Text('P键：显示/隐藏拼音', style: TextStyle(color: Colors.grey)),
            Text('X键：显示/隐藏解释', style: TextStyle(color: Colors.grey)),
            Text('←→键：浏览历史', style: TextStyle(color: Colors.grey)),
            Text('↑↓键：切换年级', style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}
