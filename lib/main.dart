import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'dart:async';
import 'package:window_manager/window_manager.dart';
import 'dart:math';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化窗口管理器
  await windowManager.ensureInitialized();

  // 设置窗口最小尺寸
  await windowManager.setMinimumSize(const Size(900, 600));
  await windowManager.setSize(const Size(900, 600)); // 设置初始窗口大小

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
        fontFamily: 'PingFang SC', // 设置默认字体
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
  String? _currentWord; // 当前显示的词语
  bool _showPinyin = false;
  bool _keepPinyin = false; // 保持显示拼音的状态
  bool _showExplanation = false;
  bool _keepExplanation = false; // 保持显示解释的状态
  bool _isInputMode = false;
  String _inputPinyin = '';
  int _currentInputIndex = 0; // 当前输入位置
  final FocusNode _focusNode = FocusNode();
  String? _currentFrom;
  List<String> _fromList = [];
  int _currentIndex = 0; // 当前词语索引
  List<String> _currentWordList = [];
  final Map<String, int> _fromLastIndex = {}; // 记录每个来源的最后序号
  final FlutterTts _flutterTts = FlutterTts();

  // 出题模式相关状态
  bool _isQuizMode = false; // 是否处于出题模式
  List<String> _quizWords = []; // 出题模式的词语列表
  bool _showAllAnswers = false; // 是否显示所有答案
  int _totalQuestions = 30; // 总题目数

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
        _fromList = _words!.values
            .map((word) => word['from'] as String)
            .toSet()
            .toList()
          ..sort((a, b) {
            // 提取年级数字
            int getGradeNumber(String str) {
              final match = RegExp(r'[一二三四五六]').firstMatch(str);
              if (match == null) return 999; // 非年级内容放在最后
              final gradeMap = {'一': 1, '二': 2, '三': 3, '四': 4, '五': 5, '六': 6};
              return gradeMap[match.group(0)] ?? 999;
            }

            final gradeA = getGradeNumber(a);
            final gradeB = getGradeNumber(b);

            if (gradeA != gradeB) {
              return gradeA.compareTo(gradeB);
            }

            // 如果年级相同，按上下册排序
            if (a.contains('上册') && b.contains('下册')) return -1;
            if (a.contains('下册') && b.contains('上册')) return 1;

            // 如果都不是年级内容，按原字符串排序
            return a.compareTo(b);
          });
        debugPrint('来源列表: $_fromList'); // 使用debugPrint替代print
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
        filteredWords = _words!.entries
            .where((entry) => entry.value['from'] == _currentFrom)
            .map((entry) => entry.key)
            .toList();
      }
    } else {
      filteredWords = _words!.entries
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
    } else {
      final currentIndex = _fromList.indexOf(_currentFrom!);

      // 循环计算新索引（支持从列表头跳到尾或从尾跳到头）
      newIndex =
          (currentIndex + direction + _fromList.length) % _fromList.length;
    }

    // 获取新来源名称
    final newFrom = _fromList[newIndex];

    // 第一阶段：立即更新来源显示
    // 这样用户可以立即看到来源已经切换
    setState(() {
      _currentFrom = newFrom;
      if (!_keepPinyin) {
        _showPinyin = false;
      }
      if (!_keepExplanation) {
        _showExplanation = false;
      }
    });

    // 第二阶段：使用延迟确保UI先更新来源显示
    // Duration.zero 意味着这段代码会在当前事件循环结束后立即执行
    // 这确保了先渲染来源变化，再渲染词语变化
    Future.delayed(Duration.zero, () {
      _updateWordListForCurrentFrom();
      _saveState(); // 保存当前状态到本地存储
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
        filteredWords = _words!.entries
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
      filteredWords = _words!.entries
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
      _currentIndex = (_currentIndex + direction + _currentWordList.length) %
          _currentWordList.length;
      _currentWord = _currentWordList[_currentIndex];
      if (!_keepPinyin) {
        _showPinyin = false;
      }
      if (!_keepExplanation) {
        _showExplanation = false;
      }
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

  // 检查输入的字母是否匹配当前拼音位置
  bool _isValidPinyinInput(String input, String fullPinyin, int position) {
    if (position >= fullPinyin.length) return false;

    // 获取当前位置的字符
    String currentChar = fullPinyin[position];

    // 如果是声调字母，检查不带声调的版本
    if (RegExp(r'[āáǎàōóǒòēéěèīíǐìūúǔùüǖǘǚǜńňǹḿ]').hasMatch(currentChar)) {
      String baseChar = currentChar
          .replaceAll(RegExp(r'[āáǎà]'), 'a')
          .replaceAll(RegExp(r'[ōóǒò]'), 'o')
          .replaceAll(RegExp(r'[ēéěè]'), 'e')
          .replaceAll(RegExp(r'[īíǐì]'), 'i')
          .replaceAll(RegExp(r'[ūúǔù]'), 'u')
          .replaceAll(RegExp(r'[üǖǘǚǜ]'), 'v')
          .replaceAll(RegExp(r'[ńňǹḿ]'), 'n');
      return input.toLowerCase() == baseChar.toLowerCase();
    }

    return input.toLowerCase() == currentChar.toLowerCase();
  }

  // 获取当前应该显示的拼音部分
  String _getDisplayPinyin() {
    if (_currentWord == null || _words == null) return '';

    String fullPinyin = _words![_currentWord]!['pinyin'].join(' ');
    if (_currentInputIndex >= fullPinyin.length) return fullPinyin;

    // 返回已输入部分和剩余部分的占位符
    return fullPinyin.substring(0, _currentInputIndex) +
        ' ' * (fullPinyin.length - _currentInputIndex);
  }

  // 开始出题模式
  void _startQuizMode() {
    if (_currentWordList.isEmpty) return;

    // 随机选择30个词语
    final random = Random();
    final words = List<String>.from(_currentWordList);
    words.shuffle(random);
    final selectedWords = words.take(_totalQuestions).toList();

    setState(() {
      _isQuizMode = true;
      _quizWords = selectedWords;
      _showAllAnswers = false;
    });
  }

  // 结束出题模式
  void _endQuizMode() {
    setState(() {
      _isQuizMode = false;
      _quizWords = [];
      _showAllAnswers = false;
      _currentWord = _currentWordList[_currentIndex];
    });
  }

  // 打印测试页面
  Future<void> _printQuizPage() async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              for (int i = 0; i < _quizWords.length; i += 3)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 12),
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      for (int j = 0; j < 3 && i + j < _quizWords.length; j++)
                        pw.Expanded(
                          child: pw.Column(
                            children: [
                              // 拼音行
                              pw.Text(
                                _words![_quizWords[i + j]]!['pinyin'].join(' '),
                                style: pw.TextStyle(
                                  fontSize: 18,
                                  color: PdfColors.grey,
                                ),
                              ),
                              pw.SizedBox(height: 8),
                              // 汉字格子行
                              pw.Row(
                                mainAxisAlignment: pw.MainAxisAlignment.center,
                                children: [
                                  for (int k = 0;
                                      k < _quizWords[i + j].length;
                                      k++)
                                    pw.Container(
                                      width: 36,
                                      height: 36,
                                      margin: const pw.EdgeInsets.symmetric(
                                          horizontal: 2),
                                      decoration: pw.BoxDecoration(
                                        border: pw.Border.all(
                                          color: PdfColors.grey,
                                          width: 1.5,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('词语学习'),
        actions: [
          if (!_isQuizMode)
            IconButton(
              icon: const Icon(Icons.quiz),
              onPressed: _startQuizMode,
              tooltip: '开始测试',
            ),
          if (_isQuizMode) ...[
            IconButton(
              icon: const Icon(Icons.print),
              onPressed: _printQuizPage,
              tooltip: '打印',
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: _endQuizMode,
              tooltip: '结束测试',
            ),
          ],
        ],
      ),
      body: GestureDetector(
        onTap: () {
          _focusNode.requestFocus();
        },
        child: KeyboardListener(
          focusNode: _focusNode,
          autofocus: true,
          onKeyEvent: (KeyEvent event) {
            if (event is KeyDownEvent) {
              if (_isQuizMode) {
                if (event.logicalKey == LogicalKeyboardKey.keyD) {
                  setState(() {
                    _showAllAnswers = !_showAllAnswers;
                  });
                }
              } else {
                if (event.logicalKey == LogicalKeyboardKey.escape) {
                  setState(() {
                    _isInputMode = !_isInputMode;
                    if (!_isInputMode) {
                      _inputPinyin = '';
                      _currentInputIndex = 0;
                    }
                  });
                } else if (_isInputMode) {
                  if (event.logicalKey == LogicalKeyboardKey.backspace) {
                    setState(() {
                      if (_currentInputIndex > 0) {
                        _currentInputIndex--;
                        _inputPinyin =
                            _inputPinyin.substring(0, _currentInputIndex);
                      }
                    });
                  } else {
                    final character = event.character;
                    if (character != null &&
                        (RegExp(r'[a-z]').hasMatch(character) ||
                            RegExp(r'[āáǎàōóǒòēéěèīíǐìūúǔùüǖǘǚǜńňǹḿ]')
                                .hasMatch(character) ||
                            character == ' ')) {
                      if (_currentWord != null && _words != null) {
                        String fullPinyin =
                            _words![_currentWord]!['pinyin'].join(' ');
                        if (_isValidPinyinInput(
                            character, fullPinyin, _currentInputIndex)) {
                          setState(() {
                            _inputPinyin += character;
                            _currentInputIndex++;
                          });
                        }
                      }
                    }
                  }
                } else if (!_isInputMode) {
                  if (event.logicalKey == LogicalKeyboardKey.space) {
                    _speakWord();
                  } else if (event.logicalKey == LogicalKeyboardKey.keyP) {
                    setState(() {
                      if (HardwareKeyboard.instance.isShiftPressed) {
                        // 大写P：切换保持显示拼音
                        _keepPinyin = !_keepPinyin;
                        _showPinyin = _keepPinyin;
                      } else {
                        // 小写p：切换当前拼音显示
                        _showPinyin = !_showPinyin;
                      }
                    });
                  } else if (event.logicalKey == LogicalKeyboardKey.keyX) {
                    setState(() {
                      if (HardwareKeyboard.instance.isShiftPressed) {
                        // 大写X：切换保持显示解释
                        _keepExplanation = !_keepExplanation;
                        _showExplanation = _keepExplanation;
                      } else {
                        // 小写x：切换当前解释显示
                        _showExplanation = !_showExplanation;
                      }
                    });
                  } else if (event.logicalKey == LogicalKeyboardKey.enter) {
                    _toggleWordCollection();
                  }

                  if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                    _navigateWord(-1);
                  } else if (event.logicalKey ==
                      LogicalKeyboardKey.arrowRight) {
                    _navigateWord(1);
                  } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                    _changeFrom(-1);
                  } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                    _changeFrom(1);
                  }
                }
              }
            }
          },
          child: Stack(
            children: [
              if (_isQuizMode)
                Container(
                  color: Colors.white,
                  child: Center(
                    child: Container(
                      width: 595, // A4纸宽度（像素）
                      height: 842, // A4纸高度（像素）
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: Colors.grey[300]!),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withOpacity(0.3),
                            spreadRadius: 2,
                            blurRadius: 5,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 试卷内容
                          Expanded(
                            child: SingleChildScrollView(
                              child: Column(
                                children: [
                                  for (int i = 0; i < _quizWords.length; i += 3)
                                    Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 12),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          for (int j = 0;
                                              j < 3 &&
                                                  i + j < _quizWords.length;
                                              j++)
                                            Expanded(
                                              child: Column(
                                                children: [
                                                  // 拼音行
                                                  Text(
                                                    _words![_quizWords[i + j]]![
                                                            'pinyin']
                                                        .join(' '),
                                                    style: const TextStyle(
                                                      fontSize: 18,
                                                      color: Colors.grey,
                                                      height: 1.2,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 8),
                                                  // 汉字格子行
                                                  Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .center,
                                                    children: [
                                                      for (int k = 0;
                                                          k <
                                                              _quizWords[i + j]
                                                                  .length;
                                                          k++)
                                                        Container(
                                                          width: 36,
                                                          height: 36,
                                                          margin:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                                  horizontal:
                                                                      2),
                                                          decoration:
                                                              BoxDecoration(
                                                            border: Border.all(
                                                                color: Colors
                                                                    .grey[400]!,
                                                                width: 1.5),
                                                          ),
                                                          child: Center(
                                                            child:
                                                                _showAllAnswers
                                                                    ? Text(
                                                                        _quizWords[i +
                                                                            j][k],
                                                                        style:
                                                                            const TextStyle(
                                                                          fontSize:
                                                                              24,
                                                                          color:
                                                                              Colors.blue,
                                                                        ),
                                                                      )
                                                                    : null,
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                Stack(
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          minWidth: 900,
                          minHeight: 600,
                        ),
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
                                        style: TextStyle(
                                          fontSize: 62,
                                          fontFamily: 'PingFang SC',
                                          letterSpacing: 2,
                                          color: _isInputMode
                                              ? Colors.grey
                                              : Colors.black,
                                        ),
                                      ),
                                      if (_savedWords.containsKey(_currentWord))
                                        const Padding(
                                          padding: EdgeInsets.only(left: 8),
                                          child: Icon(Icons.star,
                                              color: Colors.amber),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              SizedBox(
                                height: 60,
                                child: Center(
                                  child: (_showPinyin || _isInputMode) &&
                                          _words != null &&
                                          _currentWord != null
                                      ? Text(
                                          _isInputMode
                                              ? _getDisplayPinyin()
                                              : _words![_currentWord]!['pinyin']
                                                  .join(' '),
                                          style: const TextStyle(
                                            fontSize: 36,
                                            color: Colors.grey,
                                            fontFamily: 'PingFang SC',
                                            letterSpacing: 1,
                                          ),
                                        )
                                      : null,
                                ),
                              ),
                              SizedBox(
                                height: 100,
                                child: Center(
                                  child: _showExplanation &&
                                          _words != null &&
                                          _currentWord != null
                                      ? Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 40,
                                          ),
                                          child: Text(
                                            _words![_currentWord]![
                                                'explanation'],
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
                    ),
                    Positioned(
                      right: 16,
                      bottom: 16,
                      child: Text(
                        '${_currentIndex + 1}/${_currentWordList.length}',
                        style:
                            const TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                    ),
                  ],
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
            if (!_isQuizMode) ...[
              const Text('ESC键：切换输入模式', style: TextStyle(color: Colors.grey)),
              const Text('空格键：朗读词语', style: TextStyle(color: Colors.grey)),
              const Text('P键：显示/隐藏拼音', style: TextStyle(color: Colors.grey)),
              const Text('Shift+P：保持显示拼音',
                  style: TextStyle(color: Colors.grey)),
              const Text('X键：显示/隐藏解释', style: TextStyle(color: Colors.grey)),
              const Text('Shift+X：保持显示解释',
                  style: TextStyle(color: Colors.grey)),
              const Text('←→键：上一个/下一个', style: TextStyle(color: Colors.grey)),
              const Text('↑↓键：切换年级', style: TextStyle(color: Colors.grey)),
              const Text('回车键：收藏/取消收藏', style: TextStyle(color: Colors.grey)),
            ],
          ],
        ),
      ),
    );
  }
}
