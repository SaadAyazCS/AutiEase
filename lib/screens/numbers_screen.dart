import 'package:flutter/material.dart';
import '../utils/app_colors.dart';
import '../services/tts_service.dart';

class NumbersScreen extends StatefulWidget {
  const NumbersScreen({super.key});

  @override
  State<NumbersScreen> createState() => _NumbersScreenState();
}

class _NumbersScreenState extends State<NumbersScreen> {
  final TtsService tts = TtsService();

  final List<NumberItem> numbers = [
    NumberItem(number: '1', name: 'One', color: Colors.red),
    NumberItem(number: '2', name: 'Two', color: Colors.green),
    NumberItem(number: '3', name: 'Three', color: Colors.blue),
    NumberItem(number: '4', name: 'Four', color: Colors.orange),
    NumberItem(number: '5', name: 'Five', color: Colors.purple),
    NumberItem(number: '6', name: 'Six', color: Colors.pink),
    NumberItem(number: '7', name: 'Seven', color: Colors.teal),
    NumberItem(number: '8', name: 'Eight', color: Colors.amber),
    NumberItem(number: '9', name: 'Nine', color: Colors.indigo),
    NumberItem(number: '10', name: 'Ten', color: Colors.cyan),
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

  Future<void> _speak(String text) async {
    await tts.speak(text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background gradient
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.primaryBlue, AppColors.lightBlue],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),

          Positioned(bottom: 0, left: 0, right: 0, child: _buildBottomWave()),

          // Decorative shapes
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
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
                            'Numbers',
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
                      padding: const EdgeInsets.only(top: 30, bottom: 140),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        childAspectRatio: 1.0,
                      ),
                      itemCount: numbers.length,
                      itemBuilder: (context, index) {
                        return _buildNumberCard(numbers[index]);
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


Widget _buildNumberCard(NumberItem item) {
  final borderRadius = BorderRadius.circular(20);

  return Material(
    color: Colors.transparent,
    child: InkWell(
      borderRadius: borderRadius,
      onTap: () => _speak(item.name),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFE3F2FD),
          borderRadius: borderRadius,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              item.number,
              style: TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.bold,
                color: item.color,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Color.fromARGB(255, 0, 0, 0),
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.mic, size: 25, color: Color(0xFF1565C0)),
              ],
            ),
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

class NumberItem {
  final String number;
  final String name;
  final Color color;

  NumberItem({required this.number, required this.name, required this.color});
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
