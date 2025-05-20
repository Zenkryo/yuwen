import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_tts/flutter_tts.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
        fontFamily: 'STKaiti', // 设置默认字体
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
  Map<String, dynamic> _savedWords = {};
  String? _currentWord;
  bool _showPinyin = false;
  bool _showExplanation = false;
  final FocusNode _focusNode = FocusNode();
  String? _currentFrom;
  List<String> _fromList = [];
  int _currentIndex = 0;
  List<String> _currentWordList = [];
  final Map<String, int> _fromLastIndex = {}; // 记录每个来源的最后序号
  final FlutterTts _flutterTts = FlutterTts();
  bool _isInputMode = false;
  String _inputText = '';
  int _correctCount = 0;
  String _inputPinyin = '';
  int _currentPinyinIndex = 0;
  int _currentCharIndex = 0;
  List<String> _currentPinyinList = [];

  // 添加拼音映射表
  final Map<String, String> _pinyinMap = {
    'ā': 'a',
    'á': 'a',
    'ǎ': 'a',
    'à': 'a',
    'ō': 'o',
    'ó': 'o',
    'ǒ': 'o',
    'ò': 'o',
    'ē': 'e',
    'é': 'e',
    'ě': 'e',
    'è': 'e',
    'ī': 'i',
    'í': 'i',
    'ǐ': 'i',
    'ì': 'i',
    'ū': 'u',
    'ú': 'u',
    'ǔ': 'u',
    'ù': 'u',
    'ü': 'v',
    'ǖ': 'v',
    'ǘ': 'v',
    'ǚ': 'v',
    'ǜ': 'v',
    'ń': 'n',
    'ň': 'n',
    'ǹ': 'n',
    'ḿ': 'm',
  };

  // 添加获取普通ASCII拼音的方法
  String _getPlainPinyin(String pinyin) {
    String result = pinyin;
    _pinyinMap.forEach((key, value) {
      result = result.replaceAll(key, value);
    });
    return result;
  }

  @override
  void initState() {
    super.initState();
    _initTts();
    _loadWords();
  }

  @override
  void dispose() {
    _flutterTts.stop();
    _focusNode.dispose();
    super.dispose();
  }

  Future<String> get _localPath async {
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }

  Future<File> get _localFile async {
    final path = await _localPath;
    return File('$path/save.json');
  }

  Future<void> _loadSavedWords() async {
    try {
      final file = await _localFile;
      if (await file.exists()) {
        final contents = await file.readAsString();
        final data = json.decode(contents);
        setState(() {
          _savedWords = data['saved_words'] ?? {};
          _currentFrom = data['current_from'];
          _fromLastIndex.clear();
          if (data['from_last_index'] != null) {
            (data['from_last_index'] as Map<String, dynamic>).forEach((
              key,
              value,
            ) {
              _fromLastIndex[key] = value as int;
            });
          }
        });
      }
    } catch (e) {
      debugPrint('加载收藏文件失败: $e');
    }
  }

  Future<void> _saveState() async {
    final file = await _localFile;
    final data = {
      'saved_words': _savedWords,
      'current_from': _currentFrom,
      'from_last_index': _fromLastIndex,
    };
    await file.writeAsString(json.encode(data));
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
        _loadSavedWords().then((_) {
          // 只有在有收藏词语时才添加收藏选项
          if (_savedWords.isNotEmpty) {
            _fromList.add('收藏');
          }
          _currentFrom ??= _fromList.last; // 使用 ??= 操作符
          _initializeWordList();
        });
      });
    } catch (e) {
      debugPrint('加载词语文件失败: $e');
    }
  }

  void _initializeWordList() {
    if (_words == null || _words!.isEmpty || _currentFrom == null) return;

    List<String> filteredWords;
    if (_currentFrom == '收藏') {
      filteredWords = _savedWords.keys.toList();
      if (filteredWords.isEmpty) {
        _currentFrom = _fromList.firstWhere((from) => from != '收藏');
        filteredWords =
            _words!.entries
                .where((entry) => entry.value['from'] == _currentFrom)
                .map((entry) => entry.key)
                .toList();
      }
    } else {
      filteredWords =
          _words!.entries
              .where((entry) => entry.value['from'] == _currentFrom)
              .map((entry) => entry.key)
              .toList();
    }

    if (filteredWords.isEmpty) return;

    _currentWordList = filteredWords;
    _currentIndex = _fromLastIndex[_currentFrom!] ?? 0;
    if (_currentIndex >= _currentWordList.length) {
      _currentIndex = 0;
    }
    _currentWord = _currentWordList[_currentIndex];
    if (_currentWord != null && _words != null) {
      _currentPinyinList = _words![_currentWord]!['pinyin'];
    }
    setState(() {});
  }

  void _changeFrom(int direction) {
    if (_fromList.isEmpty) return;

    // 保存当前来源的序号
    if (_currentFrom != null) {
      _fromLastIndex[_currentFrom!] = _currentIndex;
    }

    // 获取当前来源的索引
    final currentIndex = _fromList.indexOf(_currentFrom!);

    // 计算新索引
    int newIndex =
        (currentIndex + direction + _fromList.length) % _fromList.length;

    // 如果目标来源是收藏，且收藏为空，则跳过
    if (_fromList[newIndex] == '收藏' && _savedWords.isEmpty) {
      // 继续向前或向后查找下一个非收藏来源
      while (_fromList[newIndex] == '收藏') {
        newIndex = (newIndex + direction + _fromList.length) % _fromList.length;
      }
    }

    setState(() {
      _currentFrom = _fromList[newIndex];
      _initializeWordList();
    });
    _saveState();
  }

  void _navigateWord(int direction) {
    if (_currentWordList.isEmpty) return;

    setState(() {
      _currentIndex =
          (_currentIndex + direction + _currentWordList.length) %
          _currentWordList.length;
      _currentWord = _currentWordList[_currentIndex];
      _showPinyin = false;
      _showExplanation = false;
    });
    // 保存当前来源的序号
    if (_currentFrom != null) {
      _fromLastIndex[_currentFrom!] = _currentIndex;
    }
    _saveState();
  }

  Future<void> _initTts() async {
    await _flutterTts.setLanguage('zh-CN');
    await _flutterTts.setSpeechRate(0.5); // 设置语速
    await _flutterTts.setVolume(1.0); // 设置音量
    await _flutterTts.setPitch(1.0); // 设置音调
  }

  Future<void> _speakWord() async {
    if (_currentWord != null) {
      await _flutterTts.speak(_currentWord!);
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
              if (event.logicalKey == LogicalKeyboardKey.escape) {
                setState(() {
                  _isInputMode = !_isInputMode;
                  if (!_isInputMode) {
                    _inputText = '';
                    _inputPinyin = '';
                    _correctCount = 0;
                    _currentPinyinIndex = 0;
                    _currentCharIndex = 0;
                  }
                });
              } else if (_isInputMode) {
                if (event.logicalKey == LogicalKeyboardKey.backspace) {
                  if (_inputPinyin.isNotEmpty) {
                    setState(() {
                      if (_currentCharIndex > 0) {
                        _currentCharIndex--;
                        _inputPinyin = _inputPinyin.substring(
                          0,
                          _inputPinyin.length - 1,
                        );
                      } else if (_currentPinyinIndex > 0) {
                        _currentPinyinIndex--;
                        _currentCharIndex =
                            _currentPinyinList[_currentPinyinIndex].length;
                        _inputPinyin = _inputPinyin.substring(
                          0,
                          _inputPinyin.length - 1,
                        );
                      }
                      _inputText = _currentWord!.substring(
                        0,
                        _currentPinyinIndex,
                      );
                      _correctCount = _inputText.length;
                    });
                  }
                } else if (event.logicalKey == LogicalKeyboardKey.space) {
                  if (_currentPinyinIndex < _currentPinyinList.length &&
                      _currentCharIndex ==
                          _currentPinyinList[_currentPinyinIndex].length) {
                    setState(() {
                      _currentPinyinIndex++;
                      _currentCharIndex = 0;
                      _inputPinyin += ' ';
                      _inputText = _currentWord!.substring(
                        0,
                        _currentPinyinIndex,
                      );
                      _correctCount = _inputText.length;
                    });
                  }
                } else if (event.character != null) {
                  final char = event.character!.toLowerCase();
                  if (_currentPinyinIndex < _currentPinyinList.length) {
                    final currentPinyin =
                        _currentPinyinList[_currentPinyinIndex];
                    final plainPinyin = _getPlainPinyin(currentPinyin);
                    if (_currentCharIndex < plainPinyin.length) {
                      final nextChar =
                          plainPinyin[_currentCharIndex].toLowerCase();
                      if (char == nextChar) {
                        setState(() {
                          _inputPinyin += currentPinyin[_currentCharIndex];
                          _currentCharIndex++;
                          if (_currentCharIndex == plainPinyin.length) {
                            _inputText = _currentWord!.substring(
                              0,
                              _currentPinyinIndex + 1,
                            );
                            _correctCount = _inputText.length;
                          }
                        });
                      }
                    }
                  }
                }
              } else {
                if (event.logicalKey == LogicalKeyboardKey.space) {
                  _speakWord();
                } else if (event.logicalKey == LogicalKeyboardKey.keyP) {
                  setState(() {
                    _showPinyin = !_showPinyin;
                  });
                } else if (event.logicalKey == LogicalKeyboardKey.keyX) {
                  setState(() {
                    _showExplanation = !_showExplanation;
                  });
                } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                  _navigateWord(-1);
                } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                  _navigateWord(1);
                } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                  _changeFrom(-1);
                } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                  _changeFrom(1);
                }
              }
            }
          },
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_currentWord != null) ...[
                      SizedBox(
                        height: 80,
                        child: Center(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (_isInputMode) ...[
                                Text(
                                  _inputText,
                                  style: const TextStyle(
                                    fontSize: 62,
                                    fontFamily: 'KaiTi',
                                    letterSpacing: 2,
                                    color: Colors.blue,
                                  ),
                                ),
                                Text(
                                  _currentWord!.substring(_inputText.length),
                                  style: const TextStyle(
                                    fontSize: 62,
                                    fontFamily: 'KaiTi',
                                    letterSpacing: 2,
                                    color: Colors.grey,
                                  ),
                                ),
                              ] else
                                Text(
                                  _currentWord!,
                                  style: const TextStyle(
                                    fontSize: 62,
                                    fontFamily: 'KaiTi',
                                    letterSpacing: 2,
                                  ),
                                ),
                              if (_savedWords.containsKey(_currentWord))
                                const Padding(
                                  padding: EdgeInsets.only(left: 8),
                                  child: Icon(Icons.star, color: Colors.amber),
                                ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(
                        height: 60,
                        child: Center(
                          child:
                              (_showPinyin || _isInputMode) && _words != null
                                  ? Text(
                                    _words![_currentWord]!['pinyin']
                                        .sublist(
                                          0,
                                          _isInputMode
                                              ? _correctCount
                                              : _words![_currentWord]!['pinyin']
                                                  .length,
                                        )
                                        .join(' '),
                                    style: const TextStyle(
                                      fontSize: 36,
                                      color: Colors.grey,
                                      fontFamily: 'Courier New',
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
                                        fontSize: 26,
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
                    if (_isInputMode)
                      Padding(
                        padding: const EdgeInsets.only(top: 20),
                        child: Text(
                          '输入模式：请输入拼音 ($_inputPinyin)',
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.orange,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Positioned(
                right: 16,
                bottom: 16,
                child: Text(
                  '${_currentIndex + 1}/${_currentWordList.length}',
                  style: const TextStyle(fontSize: 16, color: Colors.grey),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          border: Border(top: BorderSide(color: Colors.grey[300]!, width: 1)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Text(
              'ESC键：${_isInputMode ? "退出输入" : "进入输入"}模式',
              style: const TextStyle(color: Colors.grey),
            ),
            if (!_isInputMode) ...[
              const Text('空格键：朗读词语', style: TextStyle(color: Colors.grey)),
              const Text('P键：显示/隐藏拼音', style: TextStyle(color: Colors.grey)),
              const Text('X键：显示/隐藏解释', style: TextStyle(color: Colors.grey)),
              const Text('←→键：上一个/下一个', style: TextStyle(color: Colors.grey)),
              const Text('↑↓键：切换年级', style: TextStyle(color: Colors.grey)),
            ] else
              const Text('输入正确拼音显示汉字', style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}
