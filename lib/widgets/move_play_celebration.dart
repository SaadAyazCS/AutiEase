import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Full celebration screen for Move & Play completion.
class MovePlayCelebration extends StatefulWidget {
  const MovePlayCelebration({
    super.key,
    required this.title,
    required this.subtitle,
    required this.starsEarned,
    required this.starsTotal,
    required this.badgeLabel,
    required this.trophyColor,
    required this.onReplay,
    required this.onBack,
    this.replayLabel = 'Replay',
    this.backLabel = 'Back to Move & Play',
  });

  final String title;
  final String subtitle;
  final int starsEarned;
  final int starsTotal;
  final String badgeLabel;
  final Color trophyColor;
  final VoidCallback onReplay;
  final VoidCallback onBack;
  final String replayLabel;
  final String backLabel;

  @override
  State<MovePlayCelebration> createState() => _MovePlayCelebrationState();
}

class _MovePlayCelebrationState extends State<MovePlayCelebration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _confettiCtrl;

  @override
  void initState() {
    super.initState();
    _confettiCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _confettiCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.starsTotal <= 0 ? 1 : widget.starsTotal;
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF67C9F4), Color(0xFFEAF6FF)],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _confettiCtrl,
              builder: (context, _) {
                return CustomPaint(
                  painter: _ConfettiPainter(t: _confettiCtrl.value, seed: 19),
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 28, 22, 24),
              child: LayoutBuilder(
                builder: (context, c) {
                  return SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: c.maxHeight),
                      child: IntrinsicHeight(
                        child: Column(
                          children: [
                            Text(
                              widget.title,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 34,
                                fontWeight: FontWeight.w900,
                                color: Colors.white.withValues(alpha: 0.98),
                                shadows: const [
                                  Shadow(
                                    blurRadius: 12,
                                    color: Colors.black26,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              widget.subtitle,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 15,
                                height: 1.45,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF2C405B),
                              ),
                            ),
                            const SizedBox(height: 18),
                            Container(
                              width: 148,
                              height: 148,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white,
                                boxShadow: [
                                  BoxShadow(
                                    color: widget.trophyColor
                                        .withValues(alpha: 0.35),
                                    blurRadius: 28,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: Icon(
                                Icons.emoji_events_rounded,
                                size: 90,
                                color: widget.trophyColor,
                              ),
                            ),
                            const SizedBox(height: 24),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.95),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                widget.badgeLabel,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF1A1A1A),
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(total, (i) {
                                final earned = i < widget.starsEarned;
                                return Padding(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 6),
                                  child: Icon(
                                    Icons.star_rounded,
                                    size: 44,
                                    color: earned
                                        ? const Color(0xFFFFD447)
                                        : const Color(0xFFE0E6ED),
                                  ),
                                );
                              }),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Stars: ${widget.starsEarned} / $total',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Colors.grey.shade700,
                              ),
                            ),
                            const Spacer(),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: widget.onReplay,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF4EA9E3),
                                  foregroundColor: Colors.white,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: Text(
                                  widget.replayLabel,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                onPressed: widget.onBack,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF12213D),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                  side: const BorderSide(
                                    color: Color(0xFF12213D),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: Text(
                                  widget.backLabel,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({required this.t, required this.seed});

  final double t;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(seed);
    for (var i = 0; i < 54; i++) {
      final x = rnd.nextDouble() * size.width;
      final baseY = (t + rnd.nextDouble()) % 1.0;
      final y = baseY * size.height * 1.15 - size.height * 0.1;
      final r = Rect.fromCenter(
        center: Offset(x, y),
        width: 6 + rnd.nextDouble() * 8,
        height: 4 + rnd.nextDouble() * 6,
      );
      final paint = Paint()
        ..color = Color.lerp(
          const Color(0xFFFF6B9D),
          const Color(0xFF4ECDC4),
          rnd.nextDouble(),
        )!.withValues(alpha: 0.78);
      canvas.save();
      canvas.translate(r.center.dx, r.center.dy);
      canvas.rotate((t * 6 + i) * 0.4);
      canvas.translate(-r.center.dx, -r.center.dy);
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(2)),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) =>
      oldDelegate.t != t;
}

