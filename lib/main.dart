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

    setState(() {
      _currentWordList = filteredWords;
      _currentIndex = _fromLastIndex[_currentFrom!] ?? 0;
      if (_currentIndex >= _currentWordList.length) {
        _currentIndex = 0;
      }
      _currentWord = _currentWordList[_currentIndex];
      _showPinyin = false;
      _showExplanation = false;
    });
  }

  /// 切换词语来源
  /// 
  /// [direction] 方向：1表示向下切换，-1表示向上切换
  /// 
  void _changeFrom(int direction) {
    if (_fromList.isEmpty || _currentFrom == null) return;
    int newIndex = 0;
    // 如果当前来源不在来源列表中，则切换到第一个来源
    if (!_fromList.contains(_currentFrom!)) {
      newIndex = 0;
    }else{
      final currentIndex = _fromList.indexOf(_currentFrom!);

      // 循环计算新索引（支持从列表头跳到尾或从尾跳到头）
      newIndex = (currentIndex + direction + _fromList.length) % _fromList.length;
    }

    // 获取新来源名称
    final newFrom = _fromList[newIndex];
    
    // 第一阶段：立即更新来源显示
    // 这样用户可以立即看到来源已经切换
    setState(() {
      _currentFrom = newFrom;
    });
    
    // 第二阶段：使用延迟确保UI先更新来源显示
    // Duration.zero 意味着这段代码会在当前事件循环结束后立即执行
    // 这确保了先渲染来源变化，再渲染词语变化
    Future.delayed(Duration.zero, () {
      _updateWordListForCurrentFrom();
      _saveState();  // 保存当前状态到本地存储
    });
  }

  /// 根据当前来源更新词语列表
  /// 
  /// 此方法负责：
  /// 1. 获取当前来源的所有词语
  /// 2. 更新词语列表状态
  /// 3. 设置当前显示的词语
  void _updateWordListForCurrentFrom() {
    if (_words == null || _currentFrom == null) return;

    // 根据来源获取词语列表
    List<String> filteredWords;
    
    // 处理收藏来源的特殊情况
    if (_currentFrom == '收藏') {
      filteredWords = _savedWords.keys.toList();
      
      // 如果收藏为空，切换到非收藏来源
      if (filteredWords.isEmpty) {
        final nonFavoriteFrom = _fromList.firstWhere((from) => from != '收藏');
        filteredWords =
            _words!.entries
                .where((entry) => entry.value['from'] == nonFavoriteFrom)
                .map((entry) => entry.key)
                .toList();
        
        setState(() {
          _currentFrom = nonFavoriteFrom;
          _updateCurrentWordFromList(filteredWords);
        });
      } else {
        setState(() {
          _updateCurrentWordFromList(filteredWords);
        });
      }
    } else {
      // 获取普通来源的词语列表
      filteredWords =
          _words!.entries
              .where((entry) => entry.value['from'] == _currentFrom)
              .map((entry) => entry.key)
              .toList();
      
      setState(() {
        _updateCurrentWordFromList(filteredWords);
      });
    }
  }

  /// 根据词语列表更新当前显示的词语
  /// 
  /// [wordList] 词语列表
  void _updateCurrentWordFromList(List<String> wordList) {
    _currentWordList = wordList;
    
    // 恢复上次浏览位置，如果超出范围则重置为0
    _currentIndex = _fromLastIndex[_currentFrom!] ?? 0;
    if (_currentIndex >= _currentWordList.length) {
      _currentIndex = 0;
    }
    
    // 更新当前词语和拼音
    _currentWord = _currentWordList[_currentIndex];
    if (_currentWord != null && _words != null) {
      // _currentPinyinList = _words![_currentWord]!['pinyin'];
    }
    
    // 重置显示状态
    _showPinyin = false;
    _showExplanation = false;
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

  void _toggleWordCollection() {
    if (_currentWord == null) return;
    
    setState(() {
      if (_savedWords.containsKey(_currentWord)) {
        _savedWords.remove(_currentWord);
        // 如果收藏为空，从来源列表中移除收藏选项
        if (_savedWords.isEmpty && _fromList.contains('收藏')) {
          _fromList.remove('收藏');
          // // 如果当前正在显示收藏，切换到其他来源
          // if (_currentFrom == '收藏') {
          //   _currentFrom = _fromList.first;
          //   _updateWordListForCurrentFrom();
          // }
        }
      } else {
        _savedWords[_currentWord!] = _words![_currentWord];
        // 如果是第一个收藏的词语，添加收藏到来源列表
        if (_savedWords.length == 1 && !_fromList.contains('收藏')) {
          _fromList.add('收藏');
        }
      }
    });
    _saveState();
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
              } else if (event.logicalKey == LogicalKeyboardKey.enter) {
                _toggleWordCollection();
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
                              _showPinyin && _words != null && _currentWord != null
                                  ? Text(
                                    _words![_currentWord]!['pinyin'].join(' '),
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
                              _showExplanation && _words != null && _currentWord != null
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
                    if (_currentFrom != null)
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
            const Text('空格键：朗读词语', style: TextStyle(color: Colors.grey)),
            const Text('P键：显示/隐藏拼音', style: TextStyle(color: Colors.grey)),
            const Text('X键：显示/隐藏解释', style: TextStyle(color: Colors.grey)),
            const Text('←→键：上一个/下一个', style: TextStyle(color: Colors.grey)),
            const Text('↑↓键：切换年级', style: TextStyle(color: Colors.grey)),
            const Text('回车键：收藏/取消收藏', style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}
