import 'package:flutter/material.dart';
import '../models/app_models.dart';
import '../repositories/app_repositories.dart';
import '../utils/app_colors.dart';
import '../services/tts_service.dart';

class AlphabetsScreen extends StatefulWidget {
  const AlphabetsScreen({
    super.key,
    this.childId,
    this.module,
  });

  final String? childId;
  final LearningModuleModel? module;

  @override
  State<AlphabetsScreen> createState() => _AlphabetsScreenState();
}

class _AlphabetsScreenState extends State<AlphabetsScreen> {
  final TtsService tts = TtsService();
  bool _savedCompletion = false;
  bool _savingCompletion = false;

  final List<String> alphabets = [
    'A','B','C','D','E','F','G','H','I','J','K','L','M',
    'N','O','P','Q','R','S','T','U','V','W','X','Y','Z',
  ];

  @override
  void initState() {
    super.initState();
    _initTts();
  }

  Future<void> _initTts() async {
    await tts.init(
      language: "en-US",
      speechRate: 0.4,
      volume: 1.0,
      pitch: 1.0,
    );
  }

  @override
  void dispose() {
    tts.dispose();
    super.dispose();
  }

  Future<void> _speakLetter(String letter) async {
    await tts.speak(letter);
    await _recordCompletionIfNeeded();
  }

  Future<void> _recordCompletionIfNeeded() async {
    final childId = widget.childId;
    final module = widget.module;
    if (_savedCompletion ||
        _savingCompletion ||
        childId == null ||
        childId.isEmpty ||
        module == null) {
      return;
    }
    setState(() {
      _savingCompletion = true;
    });
    try {
      await AppRepositories.planner.recordActivityCompletion(
        childId: childId,
        itemId: module.id,
        moduleId: module.id,
        score: 1,
      );
      _savedCompletion = true;
    } finally {
      if (mounted) {
        setState(() {
          _savingCompletion = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.primaryBlue, Color(0xFF2592D1)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),

          Positioned(bottom: 0, left: 0, right: 0, child: _buildBottomWave()),

          Positioned(
            bottom: 50,
            left: 20,
            child: Container(width: 20, height: 20, color: AppColors.yellow),
          ),
          Positioned(
            bottom: 100,
            left: 80,
            child: const Icon(Icons.star, color: AppColors.pink, size: 24),
          ),
          Positioned(
            bottom: 60,
            right: 100,
            child: CustomPaint(
              size: const Size(20, 20),
              painter: TrianglePainter(color: AppColors.red),
            ),
          ),
          Positioned(
            bottom: 50,
            right: 30,
            child: Container(
              width: 16,
              height: 16,
              decoration: const BoxDecoration(
                color: AppColors.green,
                shape: BoxShape.circle,
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          child: const Icon(
                            Icons.arrow_back_ios_new,
                            color: AppColors.darkBlue,
                            size: 24,
                          ),
                        ),
                      ),
                      const Expanded(
                        child: Center(
                          child: Text(
                            'Alphabets',
                            style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.bold,
                              color: Color.fromARGB(255, 0, 0, 0),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 40),
                    ],
                  ),
                ),

                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: GridView.builder(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.only(top: 20, bottom: 140),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        childAspectRatio: 1.3,
                      ),
                      itemCount: alphabets.length,
                      itemBuilder: (context, index) {
                        return _buildAlphabetCard(alphabets[index]);
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlphabetCard(String letter) {
    final borderRadius = BorderRadius.circular(16);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: borderRadius,
        onTap: () => _speakLetter(letter),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFFD1C4E9),
            borderRadius: borderRadius,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                letter,
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  color: Color.fromARGB(255, 0, 0, 0),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.mic, size: 30, color: Color(0xFF1565C0)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomWave() {
    return ClipPath(
      clipper: BottomWaveClipper(),
      child: Container(
        height: 120,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF00B5FD), AppColors.primaryBlue],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
      ),
    );
  }
}

class BottomWaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    var path = Path();
    path.moveTo(0, 50);

    var firstControlPoint = Offset(size.width / 4, 0);
    var firstEndPoint = Offset(size.width / 2, 30);
    path.quadraticBezierTo(
      firstControlPoint.dx,
      firstControlPoint.dy,
      firstEndPoint.dx,
      firstEndPoint.dy,
    );

    var secondControlPoint = Offset(size.width * 3 / 4, 60);
    var secondEndPoint = Offset(size.width, 20);
    path.quadraticBezierTo(
      secondControlPoint.dx,
      secondControlPoint.dy,
      secondEndPoint.dx,
      secondEndPoint.dy,
    );

    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

class TrianglePainter extends CustomPainter {
  final Color color;
  TrianglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    var path = Path();
    path.moveTo(size.width / 2, 0);
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();

    var paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
