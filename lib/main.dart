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
  int SRSIntervalDays; // Thuật toán lặp lại ngắt quãng (SRS)
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
// MAIN HOME SCREEN WITH BOTTOM NAVIGATION
// -----------------------------------------------------------------------------
class MainHomeScreen extends StatefulWidget {
  const MainHomeScreen({super.key});

  @override
  State<MainHomeScreen> createState() => _MainHomeScreenState();
}

class _MainHomeScreenState extends State<MainHomeScreen> {
  int _selectedIndex = 0;
  List<Flashcard> _cards = [];
  int _streakDays = 0;
  String _lastStudyDate = '';

  final FlutterTts _flutterTts = FlutterTts();
  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  @override
  void initState() {
    super.initState();
    _initTTS();
    _initNotifications();
    _loadData();
  }

  // 1. TÍNH NĂNG: ĐỌC PHÁT ÂM (TTS)
  void _initTTS() async {
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.5);
  }

  void _speak(String text) async {
    if (text.isNotEmpty) {
      await _flutterTts.stop();
      await _flutterTts.speak(text);
    }
  }

  // 2. TÍNH NĂNG: THÔNG BÁO NHẮC HỌC (LOCAL NOTIFICATIONS)
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

  // LƯU & TẢI DỮ LIỆU + CHUỖI NGÀY HỌC (DAILY STREAK)
  void _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final String? cardsJson = prefs.getString('flashcards');
    if (cardsJson != null) {
      final List<dynamic> decoded = jsonDecode(cardsJson);
      _cards = decoded.map((item) => Flashcard.fromJson(item)).toList();
    } else {
      // Dữ liệu mẫu ban đầu
      _cards = [
        Flashcard(
            id: '1', question: 'Apple', answer: 'Quả táo', category: 'Trái cây'),
        Flashcard(
            id: '2', question: 'Banana', answer: 'Quả chuối', category: 'Trái cây'),
        Flashcard(
            id: '3', question: 'Computer', answer: 'Máy tính', category: 'Công nghệ'),
        Flashcard(
            id: '4', question: 'Developer', answer: 'Lập trình viên', category: 'Công nghệ'),
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
    final String encoded =
        jsonEncode(_cards.map((card) => card.toJson()).toList());
    await prefs.setString('flashcards', encoded);
    await prefs.setInt('streakDays', _streakDays);
    await prefs.setString('lastStudyDate', _lastStudyDate);
  }

  // 3. TÍNH NĂNG: CHUỖI NGÀY HỌC (DAILY STREAK)
  void _checkStreak() {
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    if (_lastStudyDate.isEmpty) return;

    final lastDate = DateTime.parse(_lastStudyDate);
    final today = DateTime.parse(todayStr);
    final difference = today.difference(lastDate).inDays;

    if (difference > 1) {
      _streakDays = 0; // Bỏ lỡ > 1 ngày -> reset streak
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

  // THÊM THẺ MỚI
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
        title: const Text('Flashcard Pro'),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_active),
            tooltip: 'Thử thông báo',
            onPressed: _scheduleNotification,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: Row(
              children: [
                const Icon(Icons.local_fire_department, color: Colors.orange),
                const SizedBox(width: 4),
                Text('$_streakDays Ngày',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
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
              onPressed: _showAddCardDialog,
              icon: const Icon(Icons.add),
              label: const Text('Thêm thẻ'),
            )
          : null,
    );
  }

  // ===========================================================================
  // TAB 1: LẬP THẺ HỌC + ANKI SRS (ĐÁNH GIÁ ĐỘ KHÓ)
  // ===========================================================================
  int _currentCardIndex = 0;
  bool _showAnswer = false;

  Widget _buildStudyTab() {
    final dueCards = _cards.where((c) => !c.isLearned).toList();

    if (dueCards.isEmpty) {
      return const Center(
        child: Text('🎉 Bạn đã hoàn thành tất cả thẻ cần học!'),
      );
    }

    if (_currentCardIndex >= dueCards.length) {
      _currentCardIndex = 0;
    }

    final card = dueCards[_currentCardIndex];

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          LinearProgressIndicator(
            value: (_currentCardIndex + 1) / dueCards.length,
          ),
          const SizedBox(height: 12),
          Text('Thẻ ${_currentCardIndex + 1} / ${dueCards.length}'),
          const SizedBox(height: 20),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _showAnswer = !_showAnswer),
              child: Card(
                elevation: 6,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        card.category,
                        style: TextStyle(color: Colors.grey[600], fontSize: 14),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        _showAnswer ? card.answer : card.question,
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: _showAnswer ? Colors.indigo : Colors.black87,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      IconButton(
                        iconSize: 36,
                        icon: const Icon(Icons.volume_up, color: Colors.indigo),
                        onPressed: () => _speak(
                            _showAnswer ? card.answer : card.question),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _showAnswer ? '(Chạm để xem câu hỏi)' : '(Chạm để lật mặt sau)',
                        style: TextStyle(color: Colors.grey[500], fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          // 4. TÍNH NĂNG: ĐÁNH GIÁ ĐỘ KHÓ (THUẬT TOÁN ANKI SRS)
          if (_showAnswer) ...[
            const Text('Đánh giá độ khó (Thuật toán Anki):',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _srsButton('Rất khó\n(1 ngày)', Colors.red, () {
                  _updateCardSRS(card, 1, false);
                }),
                _srsButton('Khó\n(3 ngày)', Colors.orange, () {
                  _updateCardSRS(card, 3, false);
                }),
                _srsButton('Tốt\n(5 ngày)', Colors.blue, () {
                  _updateCardSRS(card, 5, false);
                }),
                _srsButton('Dễ\n(Thuộc)', Colors.green, () {
                  _updateCardSRS(card, 7, true);
                }),
              ],
            ),
          ] else
            ElevatedButton(
              onPressed: () => setState(() => _showAnswer = true),
              child: const Text('Xem đáp án'),
            ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _srsButton(String text, Color color, VoidCallback onPressed) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: color.withOpacity(0.15),
        foregroundColor: color,
        side: BorderSide(color: color),
      ),
      onPressed: onPressed,
      child: Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11)),
    );
  }

  void _updateCardSRS(Flashcard card, int days, bool markLearned) {
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
  // TAB 2: CHẾ ĐỘ TRẮC NGHIỆM (QUIZ MODE)
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
              IconButton(
                icon: const Icon(Icons.volume_up),
                onPressed: () => _speak(currentCard.question),
              )
            ],
          ),
          const SizedBox(height: 20),
          Card(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(32.0),
              child: Text(
                currentCard.question,
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(height: 20),
          ..._quizOptions.map((option) => Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
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
  // TAB 3: CHẾ ĐỘ GÕ TỪ (TYPING MODE)
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
          const Text('Gõ chính xác đáp án tiếng Việt/Tiếng Anh của từ sau:',
              style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 20),
          Card(
            color: Colors.indigo.shade50,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  Text(currentCard.question,
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.volume_up),
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
              hintText: 'Nhập chính xác đáp án',
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
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
          )
        ],
      ),
    );
  }

  // ===========================================================================
  // TAB 4: QUẢN LÝ + TÌM KIẾM & LỌC (SEARCH & FILTER)
  // ===========================================================================
  String _searchQuery = '';
  String _filterCategory = 'Tất cả';

  Widget _buildManageTab() {
    final filteredCards = _cards.where((card) {
      final matchesSearch = card.question
              .toLowerCase()
              .contains(_searchQuery.toLowerCase()) ||
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
        // Thanh tìm kiếm
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Tìm kiếm câu hỏi hoặc đáp án...',
              border: OutlineInputBorder(),
            ),
            onChanged: (val) => setState(() => _searchQuery = val),
          ),
        ),
        // Thanh Lọc (Filter)
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
                  child: Icon(c.isLearned ? Icons.check : Icons.access_time,
                      color: Colors.white),
                ),
                title: Text(c.question,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('${c.answer} • [${c.category}]'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.volume_up),
                      onPressed: () => _speak(c.question),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
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

  // DIALOG THÊM THẺ MỚI
  void _showAddCardDialog() {
    final qController = TextEditingController();
    final aController = TextEditingController();
    final cController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Thêm thẻ Flashcard mới'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: qController,
                decoration: const InputDecoration(labelText: 'Mặt trước (Từ/Câu hỏi)')),
            TextField(
                controller: aController,
                decoration: const InputDecoration(labelText: 'Mặt sau (Nghĩa/Đáp án)')),
            TextField(
                controller: cController,
                decoration: const InputDecoration(labelText: 'Chủ đề (Ví dụ: Từ vựng)')),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
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

  // ===========================================================================
  // TAB 5: BIỂU ĐỒ & THỐNG KÊ (STATISTICS)
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
          const Text('Thống kê quá trình học',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Tỷ lệ thành thạo:',
                          style: TextStyle(fontWeight: FontWeight.bold)),
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
              Expanded(
                child: _statCard(
                    'Tổng số thẻ', '$total', Icons.style, Colors.blue),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _statCard(
                    'Đã thuộc', '$learned', Icons.check_circle, Colors.green),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _statCard(
                    'Đang học', '$learning', Icons.timelapse, Colors.orange),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _statCard('Daily Streak', '$_streakDays Ngày',
                    Icons.local_fire_department, Colors.deepOrange),
              ),
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
            Text(value,
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 4),
            Text(title, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
