import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Cinematic Animated Opening/Splash Screen for MultiPad
class SplashScreen extends StatefulWidget {
  final Widget nextScreen;
  final Duration minDuration;
  @visibleForTesting
  static bool debugDisableAnimations = false;

  const SplashScreen({
    super.key,
    required this.nextScreen,
    this.minDuration = const Duration(milliseconds: 1800),
  });

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final AnimationController _rotateController;
  late final AnimationController _fadeController;

  late final Animation<double> _scaleAnimation;
  late final Animation<double> _glowAnimation;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _textFadeAnimation;

  String _statusText = 'Kriptografik Bellek Başlatılıyor...';
  Timer? _statusTimer1;
  Timer? _statusTimer2;
  Timer? _navigationTimer;
  bool _hasNavigated = false;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _rotateController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 6000),
    );

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _scaleAnimation = Tween<double>(begin: 0.82, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeOutBack),
    );

    _glowAnimation = Tween<double>(begin: 0.35, end: 0.95).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOutSine),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _fadeController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    _textFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _fadeController,
        curve: const Interval(0.4, 1.0, curve: Curves.easeOut),
      ),
    );

    if (SplashScreen.debugDisableAnimations) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _navigateNext());
      return;
    }

    _fadeController.forward();
    _pulseController.repeat(reverse: true);
    _rotateController.repeat();

    _statusTimer1 = Timer(const Duration(milliseconds: 600), () {
      if (mounted) {
        setState(() => _statusText = 'Donanım Anahtarlığı Doğrulanıyor...');
      }
    });

    _statusTimer2 = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) {
        setState(() => _statusText = 'Sıfır-Bilgi Kasası Hazır');
      }
    });

    _navigationTimer = Timer(widget.minDuration, () {
      _navigateNext();
    });
  }

  void _navigateNext() {
    if (_hasNavigated || !mounted) return;
    _hasNavigated = true;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => widget.nextScreen,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeInOut),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  @override
  void dispose() {
    _statusTimer1?.cancel();
    _statusTimer2?.cancel();
    _navigationTimer?.cancel();
    _pulseController.dispose();
    _rotateController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (SplashScreen.debugDisableAnimations) {
      return widget.nextScreen;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgGradient = isDark
        ? const RadialGradient(
            center: Alignment(0.0, -0.1),
            radius: 1.1,
            colors: [
              Color(0xFF1E1B4B), // deep indigo
              Color(0xFF0F172A), // slate 900
              Color(0xFF0B0F19), // ultra obsidian
            ],
            stops: [0.0, 0.6, 1.0],
          )
        : const RadialGradient(
            center: Alignment(0.0, -0.1),
            radius: 1.1,
            colors: [
              Color(0xFFEEF2FF), // light indigo tint
              Color(0xFFF8FAFC),
              Color(0xFFE2E8F0),
            ],
            stops: [0.0, 0.6, 1.0],
          );

    return Scaffold(
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _navigateNext, // Tap anywhere to skip instantly
        child: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(gradient: bgGradient),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Ambient animated glowing backdrop rings
              AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  return CustomPaint(
                    size: const Size(360, 360),
                    painter: _SplashGlowPainter(
                      glowIntensity: _glowAnimation.value,
                      rotation: _rotateController.value * 2 * 3.1415926535,
                      isDark: isDark,
                    ),
                  );
                },
              ),

              // Center Brand Emblem & Content
              AnimatedBuilder(
                animation: _fadeController,
                builder: (context, child) {
                  return FadeTransition(
                    opacity: _fadeAnimation,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Animated Logo Squircle & Padlock
                        ScaleTransition(
                          scale: _scaleAnimation,
                          child: Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(28),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF6366F1).withOpacity(0.35),
                                  blurRadius: 32,
                                  spreadRadius: 4,
                                  offset: const Offset(0, 8),
                                ),
                                BoxShadow(
                                  color: const Color(0xFF06B6D4).withOpacity(0.25),
                                  blurRadius: 18,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(28),
                              child: Image.asset(
                                'assets/images/multipad_logo.png',
                                width: 120,
                                height: 120,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  // Fallback vector icon
                                  return Container(
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [Color(0xFF4F46E5), Color(0xFF06B6D4)],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      borderRadius: BorderRadius.circular(28),
                                    ),
                                    child: const Icon(
                                      Icons.shield_rounded,
                                      size: 64,
                                      color: Colors.white,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 28),

                        // Shimmer Brand Typography
                        ShaderMask(
                          shaderCallback: (bounds) {
                            return const LinearGradient(
                              colors: [
                                Color(0xFF818CF8), // Indigo 400
                                Color(0xFF38BDF8), // Cyan 400
                                Color(0xFF818CF8),
                              ],
                              stops: [0.0, 0.5, 1.0],
                            ).createShader(bounds);
                          },
                          child: const Text(
                            'MultiPad',
                            style: TextStyle(
                              fontSize: 34,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
                              color: Colors.white,
                            ),
                          ),
                        ),

                        const SizedBox(height: 8),

                        // Tagline
                        FadeTransition(
                          opacity: _textFadeAnimation,
                          child: Text(
                            'Sıfır-Bilgi Dijital Kasa & Kimlik Yöneticisi',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.5,
                              color: isDark
                                  ? const Color(0xFF94A3B8)
                                  : const Color(0xFF64748B),
                            ),
                          ),
                        ),

                        const SizedBox(height: 48),

                        // Dynamic Status Pulse & Mini Progress Bar
                        FadeTransition(
                          opacity: _textFadeAnimation,
                          child: Column(
                            children: [
                              SizedBox(
                                width: 140,
                                height: 3,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(2),
                                  child: LinearProgressIndicator(
                                    backgroundColor: isDark
                                        ? const Color(0xFF1E293B)
                                        : const Color(0xFFE2E8F0),
                                    valueColor: const AlwaysStoppedAnimation<Color>(
                                      Color(0xFF6366F1),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                _statusText,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: isDark
                                      ? const Color(0xFF64748B)
                                      : const Color(0xFF94A3B8),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SplashGlowPainter extends CustomPainter {
  final double glowIntensity;
  final double rotation;
  final bool isDark;

  _SplashGlowPainter({
    required this.glowIntensity,
    required this.rotation,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final baseRadius = size.width * 0.38;

    // Ambient radial pulse
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF6366F1).withOpacity(0.22 * glowIntensity),
          const Color(0xFF06B6D4).withOpacity(0.12 * glowIntensity),
          Colors.transparent,
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: baseRadius * 1.5));

    canvas.drawCircle(center, baseRadius * 1.5, glowPaint);

    // Orbiting particle dashes
    final orbitPaint = Paint()
      ..color = const Color(0xFF06B6D4).withOpacity(0.35 * glowIntensity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final dashCount = 8;
    final radius = baseRadius * 1.15;
    for (int i = 0; i < dashCount; i++) {
      final angle = rotation + (i * 2 * 3.1415926535 / dashCount);
      // Subtle orbit dots
      canvas.drawCircle(
        Offset(center.dx + radius * math.cos(angle), center.dy + radius * math.sin(angle)),
        2.0,
        orbitPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SplashGlowPainter oldDelegate) {
    return oldDelegate.glowIntensity != glowIntensity ||
        oldDelegate.rotation != rotation ||
        oldDelegate.isDark != isDark;
  }
}
