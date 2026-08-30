import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FlashcardApp());
}

class FlashcardApp extends StatelessWidget {
  const FlashcardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pro Flashcard',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.light,
        // Căn chỉnh cỡ chữ NavigationBar để "Trắc nghiệm" không bị rớt dòng gây lệch icon
        navigationBarTheme: NavigationBarThemeData(
          labelTextStyle: WidgetStateProperty.all(
            const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, overflow: TextOverflow.ellipsis),
          ),
        ),
      ),
      home: const MainHomeScreen(),
    );
  }
}

// -----------------------------------------------------------------------------
// MODEL: FLASHCARD
// -----------------------------------------------------------------------------
class Flashcard {
  String id;
  String question;
  String answer;
  String category;
  bool isLearned;
  int SRSIntervalDays;
  DateTime nextReviewDate;

  Flashcard({
    required this.id,
    required this.question,
    required this.answer,
    this.category = 'Từ vựng',
    this.isLearned = false,
    this.SRSIntervalDays = 1,
    DateTime? nextReviewDate,
  }) : nextReviewDate = nextReviewDate ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'question': question,
        'answer': answer,
        'category': category,
        'isLearned': isLearned,
        'SRSIntervalDays': SRSIntervalDays,
        'nextReviewDate': nextReviewDate.toIso8601String(),
      };

  factory Flashcard.fromJson(Map<String, dynamic> json) => Flashcard(
        id: json['id'],
        question: json['question'],
        answer: json['answer'],
        category: json['category'] ?? 'Từ vựng',
        isLearned: json['isLearned'] ?? false,
        SRSIntervalDays: json['SRSIntervalDays'] ?? 1,
        nextReviewDate: json['nextReviewDate'] != null
            ? DateTime.parse(json['nextReviewDate'])
            : DateTime.now(),
      );
}

// -----------------------------------------------------------------------------
// MAIN HOME SCREEN WITH BOTTOM NAVIGATION & ANIMATION
// -----------------------------------------------------------------------------
class MainHomeScreen extends StatefulWidget {
  const MainHomeScreen({super.key});

  @override
  State<MainHomeScreen> createState() => _MainHomeScreenState();
}

class _MainHomeScreenState extends State<MainHomeScreen>
    with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;
  List<Flashcard> _cards = [];
  int _streakDays = 0;
  String _lastStudyDate = '';
  String _lastSpokenId = '';

  final FlutterTts _flutterTts = FlutterTts();
  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  late AnimationController _flipController;
  late Animation<double> _flipAnimation;

  @override
  void initState() {
    super.initState();
    _initTTS();
    _initNotifications();
    _loadData();

    _flipController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _flipAnimation = Tween<double>(begin: 0, end: pi).animate(
      CurvedAnimation(parent: _flipController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _flipController.dispose();
    super.dispose();
  }

  void _toggleCardFlip() {
    if (_showAnswer) {
      _flipController.reverse();
    } else {
      _flipController.forward();
    }
    setState(() {
      _showAnswer = !_showAnswer;
    });
  }

  void _initTTS() async {
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.45);
  }

  void _speak(String text) async {
    if (text.isNotEmpty) {
      await _flutterTts.stop();
      await _flutterTts.speak(text);
    }
  }

  void _autoSpeakCard(Flashcard card) {
    if (_lastSpokenId != card.id && !_showAnswer) {
      _lastSpokenId = card.id;
      _speak(card.question);
    }
  }

  void _initNotifications() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await _notificationsPlugin.initialize(initSettings);
  }

  void _scheduleNotification() async {
    const androidDetails = AndroidNotificationDetails(
      'daily_reminder',
      'Nhắc nhở học tập',
      channelDescription: 'Thông báo nhắc ôn tập Flashcard mỗi ngày',
      importance: Importance.high,
      priority: Priority.high,
    );
    const details = NotificationDetails(android: androidDetails);

    await _notificationsPlugin.show(
      0,
      'Đã đến giờ ôn tập Flashcard! 📚',
      'Hãy dành 5 phút hôm nay để giữ chuỗi Daily Streak nhé!',
      details,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã kích hoạt thông báo nhắc học!')),
      );
    }
  }

  void _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final String? cardsJson = prefs.getString('flashcards');
    if (cardsJson != null) {
      final List<dynamic> decoded = jsonDecode(cardsJson);
      _cards = decoded.map((item) => Flashcard.fromJson(item)).toList();
    } else {
      _cards = [
        Flashcard(id: '1', question: 'Apple', answer: 'Quả táo', category: 'Trái cây'),
        Flashcard(id: '2', question: 'Banana', answer: 'Quả chuối', category: 'Trái cây'),
        Flashcard(id: '3', question: 'Computer', answer: 'Máy tính', category: 'Công nghệ'),
        Flashcard(id: '4', question: 'Developer', answer: 'Lập trình viên', category: 'Công nghệ'),
      ];
      _saveData();
    }

    _streakDays = prefs.getInt('streakDays') ?? 0;
    _lastStudyDate = prefs.getString('lastStudyDate') ?? '';
    _checkStreak();
    setState(() {});
  }

  void _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    final String encoded = jsonEncode(_cards.map((card) => card.toJson()).toList());
    await prefs.setString('flashcards', encoded);
    await prefs.setInt('streakDays', _streakDays);
    await prefs.setString('lastStudyDate', _lastStudyDate);
  }

  void _checkStreak() {
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    if (_lastStudyDate.isEmpty) return;

    final lastDate = DateTime.parse(_lastStudyDate);
    final today = DateTime.parse(todayStr);
    final difference = today.difference(lastDate).inDays;

    if (difference > 1) {
      _streakDays = 0;
    }
  }

  void _updateStreak() {
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    if (_lastStudyDate != todayStr) {
      _streakDays += 1;
      _lastStudyDate = todayStr;
      _saveData();
      setState(() {});
    }
  }

  void _addCard(String question, String answer, String category) {
    setState(() {
      _cards.add(Flashcard(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        question: question,
        answer: answer,
        category: category.isEmpty ? 'Chung' : category,
      ));
    });
    _saveData();
  }

  // TÍNH NĂNG IMPORT TỪ EXCEL: Nhận diện dấu Tab (\t) khi copy 2 cột trên Excel/Google Sheets
  void _bulkAddCards(String rawText, String defaultCategory) {
    final lines = rawText.split('\n');
    int addedCount = 0;

    for (var line in lines) {
      if (line.trim().isEmpty) continue;

      List<String> parts = [];
      // Kiểm tra tab \t trước để hỗ trợ Excel, sau đó mới tới các dấu phân cách khác
      if (line.contains('\t')) {
        parts = line.split('\t');
      } else if (line.contains('-')) {
        parts = line.split('-');
      } else if (line.contains(':')) {
        parts = line.split(':');
      } else if (line.contains(',')) {
        parts = line.split(',');
      }

      if (parts.length >= 2) {
        final q = parts[0].trim();
        final a = parts[1].trim();
        if (q.isNotEmpty && a.isNotEmpty) {
          _cards.add(Flashcard(
            id: '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(10000)}',
            question: q,
            answer: a,
            category: defaultCategory.isEmpty ? 'Chung' : defaultCategory,
          ));
          addedCount++;
        }
      }
    }

    if (addedCount > 0) {
      _saveData();
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ Đã thêm thành công $addedCount từ mới!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _buildStudyTab(),
      _buildQuizTab(),
      _buildTypingTab(),
      _buildManageTab(),
      _buildStatsTab(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Flashcard Pro', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_active_outlined),
            tooltip: 'Thử thông báo',
            onPressed: _scheduleNotification,
          ),
          Container(
            margin: const EdgeInsets.only(right: 16, left: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Row(
              children: [
                const Icon(Icons.local_fire_department, color: Colors.orange, size: 20),
                const SizedBox(width: 4),
                Text('$_streakDays Ngày',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
              ],
            ),
          )
        ],
      ),
      body: pages[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (idx) => setState(() => _selectedIndex = idx),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.style), label: 'Thẻ học'),
          NavigationDestination(icon: Icon(Icons.quiz), label: 'Trắc nghiệm'),
          NavigationDestination(icon: Icon(Icons.keyboard), label: 'Gõ từ'),
          NavigationDestination(icon: Icon(Icons.list_alt), label: 'Quản lý'),
          NavigationDestination(icon: Icon(Icons.bar_chart), label: 'Thống kê'),
        ],
      ),
      floatingActionButton: _selectedIndex == 3
          ? FloatingActionButton.extended(
              onPressed: _showAddOptionsModal,
              icon: const Icon(Icons.add),
              label: const Text('Thêm từ'),
            )
          : null,
    );
  }

  // ===========================================================================
  // TAB 1: THẺ HỌC
  // ===========================================================================
  int _currentCardIndex = 0;
  bool _showAnswer = false;

  Widget _buildStudyTab() {
    final dueCards = _cards.where((c) => !c.isLearned).toList();

    if (dueCards.isEmpty) {
      return const Center(
        child: Text('🎉 Bạn đã hoàn thành tất cả thẻ cần học!',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      );
    }

    if (_currentCardIndex >= dueCards.length) {
      _currentCardIndex = 0;
    }

    final card = dueCards[_currentCardIndex];

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoSpeakCard(card);
    });

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: (_currentCardIndex + 1) / dueCards.length,
                    minHeight: 10,
                    backgroundColor: Colors.indigo.shade50,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Thẻ ${_currentCardIndex + 1}/${dueCards.length}',
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo),
              ),
            ],
          ),
          const SizedBox(height: 16),

          Expanded(
            child: GestureDetector(
              onTap: _toggleCardFlip,
              child: AnimatedBuilder(
                animation: _flipAnimation,
                builder: (context, child) {
                  final angle = _flipAnimation.value;
                  final isFront = angle < (pi / 2);

                  return Transform(
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.001)
                      ..rotateY(angle),
                    alignment: Alignment.center,
                    child: isFront
                        ? _buildCardFace(
                            category: card.category,
                            text: card.question,
                            isAnswer: false,
                            onSpeak: () => _speak(card.question),
                          )
                        : Transform(
                            transform: Matrix4.identity()..rotateY(pi),
                            alignment: Alignment.center,
                            child: _buildCardFace(
                              category: card.category,
                              text: card.answer,
                              isAnswer: true,
                              onSpeak: () => _speak(card.answer),
                            ),
                          ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 16),

          // NÚT ĐÁNH GIÁ ĐỌC GỌN (ĐÃ BỎ "1 NGÀY", "2 NGÀY")
          if (_showAnswer) ...[
            const Text(
              'Đánh giá độ khó:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _srsButton('Rất khó', Colors.red.shade600, () {
                  _updateCardSRS(card, 1, false);
                }),
                _srsButton('Khó', Colors.orange.shade800, () {
                  _updateCardSRS(card, 3, false);
                }),
                _srsButton('Tốt', Colors.blue.shade700, () {
                  _updateCardSRS(card, 5, false);
                }),
                _srsButton('Dễ', Colors.green.shade700, () {
                  _updateCardSRS(card, 7, true);
                }),
              ],
            ),
          ] else
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.flip),
                label: const Text('Xem đáp án', style: TextStyle(fontSize: 16)),
                onPressed: _toggleCardFlip,
              ),
            ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _buildCardFace({
    required String category,
    required String text,
    required bool isAnswer,
    required VoidCallback onSpeak,
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Chip(
                  label: Text(category, style: const TextStyle(fontSize: 12)),
                  backgroundColor: isAnswer ? Colors.green.shade50 : Colors.indigo.shade50,
                  side: BorderSide.none,
                ),
                IconButton.filledTonal(
                  icon: const Icon(Icons.volume_up_rounded),
                  color: isAnswer ? Colors.green.shade700 : Colors.indigo,
                  onPressed: onSpeak,
                  tooltip: 'Nghe phát âm',
                ),
              ],
            ),
            const Spacer(),
            Text(
              text,
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: isAnswer ? Colors.green.shade800 : Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.flip_camera_android, size: 16, color: Colors.grey[500]),
                const SizedBox(width: 6),
                Text(
                  isAnswer ? 'Chạm để lật mặt trước' : 'Chạm để lật mặt sau',
                  style: TextStyle(color: Colors.grey[500], fontSize: 13),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _srsButton(String text, Color color, VoidCallback onPressed) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3.0),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 2,
          ),
          onPressed: onPressed,
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }

  void _updateCardSRS(Flashcard card, int days, bool markLearned) {
    _flipController.value = 0.0;
    setState(() {
      card.SRSIntervalDays = days;
      card.nextReviewDate = DateTime.now().add(Duration(days: days));
      if (markLearned) card.isLearned = true;
      _showAnswer = false;
      _currentCardIndex++;
    });
    _updateStreak();
    _saveData();
  }

  // ===========================================================================
  // TAB 2: TRẮC NGHIỆM
  // ===========================================================================
  int _quizIndex = 0;
  int _quizScore = 0;
  List<String> _quizOptions = [];

  Widget _buildQuizTab() {
    if (_cards.length < 4) {
      return const Center(
        child: Text('Cần ít nhất 4 thẻ trong ứng dụng để chơi Trắc nghiệm!'),
      );
    }

    final currentCard = _cards[_quizIndex % _cards.length];

    if (_quizOptions.isEmpty) {
      _generateQuizOptions(currentCard);
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Điểm: $_quizScore', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              IconButton.filledTonal(
                icon: const Icon(Icons.volume_up),
                onPressed: () => _speak(currentCard.question),
              )
            ],
          ),
          const SizedBox(height: 20),
          Card(
            elevation: 2,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(32.0),
              child: Text(
                currentCard.question,
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(height: 20),
          ..._quizOptions.map((option) => Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => _checkQuizAnswer(option, currentCard.answer),
                  child: Text(option, style: const TextStyle(fontSize: 18)),
                ),
              )),
        ],
      ),
    );
  }

  void _generateQuizOptions(Flashcard correctCard) {
    final random = Random();
    Set<String> options = {correctCard.answer};

    while (options.length < 4) {
      final randomCard = _cards[random.nextInt(_cards.length)];
      options.add(randomCard.answer);
    }

    _quizOptions = options.toList()..shuffle();
  }

  void _checkQuizAnswer(String selected, String correct) {
    bool isCorrect = selected == correct;
    if (isCorrect) _quizScore += 10;

    _updateStreak();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(isCorrect ? '✅ Chính xác! +10 điểm' : '❌ Sai rồi! Đáp án là: $correct'),
        duration: const Duration(milliseconds: 1200),
      ),
    );

    setState(() {
      _quizIndex++;
      _quizOptions.clear();
    });
  }

  // ===========================================================================
  // TAB 3: GÕ TỪ
  // ===========================================================================
  final TextEditingController _typingController = TextEditingController();
  int _typingIndex = 0;

  Widget _buildTypingTab() {
    if (_cards.isEmpty) return const Center(child: Text('Chưa có thẻ nào!'));

    final currentCard = _cards[_typingIndex % _cards.length];

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          const Text('Gõ chính xác đáp án tiếng Việt/Tiếng Anh:', style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 16),
          Card(
            color: Colors.indigo.shade50,
            elevation: 0,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  Text(currentCard.question,
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.volume_up, color: Colors.indigo),
                    onPressed: () => _speak(currentCard.question),
                  )
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _typingController,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Nhập đáp án...',
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.check),
              label: const Text('Kiểm tra'),
              onPressed: () {
                final userInput = _typingController.text.trim().toLowerCase();
                final correctAnswer = currentCard.answer.trim().toLowerCase();

                bool isCorrect = userInput == correctAnswer;
                _updateStreak();

                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text(isCorrect ? '🎉 Chính xác!' : '❌ Chưa chính xác!'),
                    content: Text(isCorrect
                        ? 'Bạn gõ rất chuẩn!'
                        : 'Đáp án đúng phải là: ${currentCard.answer}'),
                    actions: [
                      TextButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _typingController.clear();
                          setState(() => _typingIndex++);
                        },
                        child: const Text('Tiếp tục'),
                      )
                    ],
                  ),
                );
              },
            ),
          )
        ],
      ),
    );
  }

  // ===========================================================================
  // TAB 4: QUẢN LÝ
  // ===========================================================================
  String _searchQuery = '';
  String _filterCategory = 'Tất cả';

  Widget _buildManageTab() {
    final filteredCards = _cards.where((card) {
      final matchesSearch = card.question.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          card.answer.toLowerCase().contains(_searchQuery.toLowerCase());

      if (_filterCategory == 'Đã thuộc') {
        return matchesSearch && card.isLearned;
      } else if (_filterCategory == 'Đang học') {
        return matchesSearch && !card.isLearned;
      }
      return matchesSearch;
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Tìm kiếm từ vựng...',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(vertical: 10),
            ),
            onChanged: (val) => setState(() => _searchQuery = val),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: ['Tất cả', 'Đang học', 'Đã thuộc'].map((cat) {
              final isSelected = _filterCategory == cat;
              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: FilterChip(
                  label: Text(cat),
                  selected: isSelected,
                  onSelected: (_) => setState(() => _filterCategory = cat),
                ),
              );
            }).toList(),
          ),
        ),
        const Divider(),
        Expanded(
          child: ListView.builder(
            itemCount: filteredCards.length,
            itemBuilder: (ctx, idx) {
              final c = filteredCards[idx];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: c.isLearned ? Colors.green : Colors.orange,
                  child: Icon(c.isLearned ? Icons.check : Icons.access_time, color: Colors.white),
                ),
                title: Text(c.question, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('${c.answer} • [${c.category}]'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.volume_up),
                      onPressed: () => _speak(c.question),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () {
                        setState(() => _cards.remove(c));
                        _saveData();
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showAddOptionsModal() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add_card, color: Colors.indigo),
              title: const Text('Thêm 1 thẻ mới'),
              onTap: () {
                Navigator.pop(ctx);
                _showAddSingleCardDialog();
              },
            ),
            ListTile(
              leading: const Icon(Icons.table_chart, color: Colors.indigo),
              title: const Text('Thêm từ hàng loạt (Excel)'),
              subtitle: const Text('Copy 2 cột Từ & Nghĩa trên Excel dán vào đây'),
              onTap: () {
                Navigator.pop(ctx);
                _showBulkAddDialog();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showAddSingleCardDialog() {
    final qController = TextEditingController();
    final aController = TextEditingController();
    final cController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Thêm thẻ mới'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: qController, decoration: const InputDecoration(labelText: 'Mặt trước (Từ mới)')),
            TextField(controller: aController, decoration: const InputDecoration(labelText: 'Mặt sau (Nghĩa)')),
            TextField(controller: cController, decoration: const InputDecoration(labelText: 'Chủ đề')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          ElevatedButton(
            onPressed: () {
              if (qController.text.isNotEmpty && aController.text.isNotEmpty) {
                _addCard(qController.text, aController.text, cController.text);
                Navigator.pop(ctx);
              }
            },
            child: const Text('Thêm'),
          )
        ],
      ),
    );
  }

  // DIALOG HỖ TRỢ COPY TRỰC TIẾP TỪ EXCEL / GOOGLE SHEETS
  void _showBulkAddDialog() {
    final bulkController = TextEditingController();
    final catController = TextEditingController(text: 'Từ vựng');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Thêm từ hàng loạt'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '📌 Cách dùng:\n1. Chọn 2 cột (Từ & Nghĩa) trên Excel / Google Sheets rồi bấm Ctrl+C.\n2. Dán (Ctrl+V) trực tiếp vào ô bên dưới.\n(Hoặc nhập theo cú pháp: Từ - Nghĩa)',
                style: TextStyle(fontSize: 12, color: Colors.black87),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: catController,
                decoration: const InputDecoration(
                  labelText: 'Chủ đề chung',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: bulkController,
                maxLines: 8,
                decoration: const InputDecoration(
                  hintText: 'Dán dữ liệu từ Excel vào đây...',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          ElevatedButton(
            onPressed: () {
              if (bulkController.text.isNotEmpty) {
                _bulkAddCards(bulkController.text, catController.text);
                Navigator.pop(ctx);
              }
            },
            child: const Text('Thêm tất cả'),
          )
        ],
      ),
    );
  }

  // ===========================================================================
  // TAB 5: THỐNG KÊ
  // ===========================================================================
  Widget _buildStatsTab() {
    final total = _cards.length;
    final learned = _cards.where((c) => c.isLearned).length;
    final learning = total - learned;
    final progress = total == 0 ? 0.0 : (learned / total);

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Thống kê quá trình học', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Tỷ lệ thành thạo:', style: TextStyle(fontWeight: FontWeight.bold)),
                      Text('${(progress * 100).toStringAsFixed(1)}%'),
                    ],
                  ),
                  const SizedBox(height: 10),
                  LinearProgressIndicator(
                    value: progress,
                    minHeight: 10,
                    borderRadius: BorderRadius.circular(5),
                    backgroundColor: Colors.grey[300],
                    color: Colors.green,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: _statCard('Tổng số thẻ', '$total', Icons.style, Colors.blue)),
              const SizedBox(width: 12),
              Expanded(child: _statCard('Đã thuộc', '$learned', Icons.check_circle, Colors.green)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _statCard('Đang học', '$learning', Icons.timelapse, Colors.orange)),
              const SizedBox(width: 12),
              Expanded(child: _statCard('Daily Streak', '$_streakDays Ngày', Icons.local_fire_department, Colors.deepOrange)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statCard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 4),
            Text(title, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
