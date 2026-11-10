import 'dart:math';
import 'package:flutter/material.dart';

class EasterEggDialog extends StatefulWidget {
  const EasterEggDialog({super.key});

  @override
  State<EasterEggDialog> createState() => _EasterEggDialogState();
}

class _EasterEggDialogState extends State<EasterEggDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<_Particle> _particles = [];
  final Random _rnd = Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();

    // Create 60 confetti particles
    for (int i = 0; i < 60; i++) {
      _particles.add(_Particle(
        x: _rnd.nextDouble(),
        y: -_rnd.nextDouble(),
        vx: (_rnd.nextDouble() - 0.5) * 0.4,
        vy: 0.3 + _rnd.nextDouble() * 0.7,
        size: 6 + _rnd.nextDouble() * 8,
        color: [
          Colors.redAccent,
          Colors.pinkAccent,
          Colors.purpleAccent,
          Colors.blueAccent,
          Colors.amber,
          Colors.tealAccent,
          Colors.orangeAccent,
        ][_rnd.nextInt(7)],
        rotation: _rnd.nextDouble() * 2 * pi,
        rotationSpeed: (_rnd.nextDouble() - 0.5) * 4,
      ));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final catColor = isDark ? Colors.white : Colors.black87;
    final catBorder = isDark ? Colors.black26 : Colors.white24;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(20),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Confetti Particle Canvas
          AnimatedBuilder(
            animation: _controller,
            builder: (ctx, _) {
              return CustomPaint(
                size: const Size(420, 500),
                painter: _ConfettiPainter(_particles, _controller.value),
              );
            },
          ),

          // Main Card
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            elevation: 12,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Animated Cat & Heart
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Cat Container
                      Container(
                        width: 90,
                        height: 90,
                        decoration: BoxDecoration(
                          color: catColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: catBorder, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: isDark ? Colors.white24 : Colors.black26,
                              blurRadius: 16,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            isDark ? '🐱' : '🐈‍⬛',
                            style: const TextStyle(fontSize: 48),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      // Beating Heart
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.9, end: 1.25),
                        duration: const Duration(milliseconds: 600),
                        curve: Curves.easeInOut,
                        builder: (ctx, scale, child) {
                          return Transform.scale(scale: scale, child: child);
                        },
                        child: const Text('❤️', style: TextStyle(fontSize: 44)),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Cat Art Ascii
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      isDark ? '(=^･ω･^=)🐾\nBeyaz Kedi Gizli Modu' : '(=^･ω･^=)🐾\nSiyah Kedi Gizli Modu',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  const Text(
                    '🎉 Gizli Sürpriz Keşfedildi!',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'MultiPad, WycDev tarafından en yüksek güvenlik ve uçtan uca şifreleme standartlarıyla senin için özel geliştirildi.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: Colors.grey, height: 1.4),
                  ),

                  const SizedBox(height: 22),

                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Miyav! Teşekkürler'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Particle {
  double x;
  double y;
  double vx;
  double vy;
  double size;
  Color color;
  double rotation;
  double rotationSpeed;

  _Particle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.size,
    required this.color,
    required this.rotation,
    required this.rotationSpeed,
  });
}

class _ConfettiPainter extends CustomPainter {
  final List<_Particle> particles;
  final double animationProgress;

  _ConfettiPainter(this.particles, this.animationProgress);

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final currentY = ((p.y + p.vy * animationProgress * 2) % 1.2) * size.height;
      final currentX = ((p.x + p.vx * animationProgress) % 1.0) * size.width;

      final paint = Paint()..color = p.color;
      canvas.save();
      canvas.translate(currentX, currentY);
      canvas.rotate(p.rotation + p.rotationSpeed * animationProgress);
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.6),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) => true;
}
