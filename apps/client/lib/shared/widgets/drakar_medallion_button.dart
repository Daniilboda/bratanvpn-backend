import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Drakar connect control: medallion on top, rays + textured gold rim behind.
class DrakarMedallionButton extends StatefulWidget {
  const DrakarMedallionButton({
    super.key,
    required this.connected,
    required this.onTap,
    this.buttonKey,
    this.diameter = 168,
  });

  final bool connected;
  final VoidCallback onTap;
  final Key? buttonKey;
  final double diameter;

  static const String medallionAsset = 'assets/drakar/medallion.png';
  static const String raysAsset = 'assets/drakar/rays.png';

  /// Opaque medallion disc radius as a fraction of the asset half-size
  /// (measured from `medallion.png`: ~440px / 512px).
  static const double contentRadiusFactor = 0.859;

  @override
  State<DrakarMedallionButton> createState() => _DrakarMedallionButtonState();
}

class _DrakarMedallionButtonState extends State<DrakarMedallionButton>
    with TickerProviderStateMixin {
  bool _pressed = false;
  late final AnimationController _breath;
  late final AnimationController _shimmer;

  @override
  void initState() {
    super.initState();
    _breath = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3800),
    );
    _shimmer = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 7000),
    );
    if (widget.connected) {
      _startBreathing();
    }
  }

  @override
  void didUpdateWidget(covariant DrakarMedallionButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.connected && !oldWidget.connected) {
      _startBreathing();
    } else if (!widget.connected && oldWidget.connected) {
      _stopBreathing();
    }
  }

  void _startBreathing() {
    _breath.repeat();
    _shimmer.repeat();
  }

  void _stopBreathing() {
    _breath
      ..stop()
      ..value = 0;
    _shimmer
      ..stop()
      ..value = 0;
  }

  @override
  void dispose() {
    _breath.dispose();
    _shimmer.dispose();
    super.dispose();
  }

  /// Smooth inhale/exhale in 0..1 from a repeating 0..1 controller.
  double _sin01(AnimationController c) =>
      0.5 + 0.5 * math.sin(c.value * math.pi * 2);

  @override
  Widget build(BuildContext context) {
    final raysSize = widget.diameter * 2.35;
    final hitSize = widget.diameter;
    // Glow canvas matches rays so the faint veil can reach ray tips.
    final glowSize = raysSize;
    final rimRadius = hitSize / 2 * DrakarMedallionButton.contentRadiusFactor;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? 0.94 : 1.0,
          duration: const Duration(milliseconds: 90),
          curve: Curves.easeOutCubic,
          child: SizedBox(
            key: widget.buttonKey,
            width: hitSize,
            height: hitSize,
            child: AnimatedBuilder(
              animation: Listenable.merge([_breath, _shimmer]),
              builder: (context, _) {
                final connected = widget.connected;
                final breath = connected ? _sin01(_breath) : 0.0;
                final shimmer = connected ? _sin01(_shimmer) : 0.0;
                // Slow drift for smoke angles (radians).
                final texturePhase = connected ? _shimmer.value * math.pi * 2 : 0.0;

                return Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    Positioned(
                      left: (hitSize - raysSize) / 2,
                      top: (hitSize - raysSize) / 2,
                      width: raysSize,
                      height: raysSize,
                      child: IgnorePointer(
                        child: Opacity(
                          opacity: connected ? (0.72 + 0.28 * breath) : 0.0,
                          child: Transform.scale(
                            scale: connected ? (1.0 + 0.04 * breath) : 1.0,
                            child: Image.asset(
                              DrakarMedallionButton.raysAsset,
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.high,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: (hitSize - glowSize) / 2,
                      top: (hitSize - glowSize) / 2,
                      width: glowSize,
                      height: glowSize,
                      child: IgnorePointer(
                        child: Opacity(
                          opacity: connected ? 1.0 : 0.0,
                          child: CustomPaint(
                            size: Size.square(glowSize),
                            painter: _TexturedGoldRimPainter(
                              rimRadius: rimRadius,
                              intensity: connected
                                  ? 0.55 + 0.45 * breath
                                  : 0.0,
                              bloomExtra: connected
                                  ? 0.85 + 0.35 * breath
                                  : 0.0,
                              texturePhase: texturePhase,
                              shimmer: shimmer,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Transform.scale(
                      scale: connected ? (1.0 + 0.012 * breath) : 1.0,
                      child: Image.asset(
                        DrakarMedallionButton.medallionAsset,
                        width: hitSize,
                        height: hitSize,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Gold bloom that starts at [rimRadius] and only radiates outward.
class _TexturedGoldRimPainter extends CustomPainter {
  _TexturedGoldRimPainter({
    required this.rimRadius,
    required this.intensity,
    required this.bloomExtra,
    required this.texturePhase,
    required this.shimmer,
  });

  final double rimRadius;
  final double intensity;
  final double bloomExtra;
  final double texturePhase;
  final double shimmer;

  // Цвета: 0xFFRRGGBB. Темнее рефа, текстура та же.
  static const Color _deep = Color(0xFF3A1E01); // хвост снаружи
  static const Color _mid = Color(0xFF7A4E18); // дым обода
  static const Color _bright = Color(0xFF9A6410); // плотнее у края
  static const Color _hot = Color(0xFF8A5814); // уплотнения дыма

  @override
  void paint(Canvas canvas, Size size) {
    if (intensity <= 0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final i = intensity.clamp(0.0, 1.0);
    final rim = rimRadius;
    // Quiet secondary amplitude for living smoke (does not flash).
    final smokeBoost = 0.85 + 0.15 * shimmer;
    // Core metrics stay tied to the medallion, not the full rays canvas.
    final medalDiameter =
        2 * rim / DrakarMedallionButton.contentRadiusFactor;
    final coreRef = medalDiameter * 1.65;

    canvas.save();
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addOval(Rect.fromCircle(center: center, radius: rim - 0.5));
    canvas.clipPath(outside);

    // Faint veil to ray tips — barely visible, does not boost rim brightness.
    final veilReach = size.shortestSide / 2;
    final veilBreath = 0.7 + 0.3 * i;
    final veil = Paint()
      ..shader = ui.Gradient.radial(
        center,
        veilReach,
        [
          _mid.withValues(alpha: 0.0),
          _mid.withValues(alpha: 0.0),
          _mid.withValues(alpha: 0.08 * i * veilBreath),
          _deep.withValues(alpha: 0.035 * i * veilBreath),
          _deep.withValues(alpha: 0.018 * i * veilBreath),
          _deep.withValues(alpha: 0.0),
        ],
        [
          0.0,
          (rim / veilReach).clamp(0.0, 1.0),
          ((rim + coreRef * 0.04) / veilReach).clamp(0.0, 1.0),
          ((rim + coreRef * 0.22) / veilReach).clamp(0.0, 1.0),
          0.92,
          1.0,
        ],
      );
    canvas.drawCircle(center, veilReach, veil);

    // Dense core bloom near the medallion rim only.
    final outerReach = rim + coreRef * 0.16 * bloomExtra;

    final bloom = Paint()
      ..shader = ui.Gradient.radial(
        center,
        outerReach,
        [
          _mid.withValues(alpha: 0.0),
          _bright.withValues(alpha: 0.0),
          _bright.withValues(alpha: 0.28 * i),
          _mid.withValues(alpha: 0.20 * i),
          _deep.withValues(alpha: 0.0),
        ],
        [
          0.0,
          (rim / outerReach).clamp(0.0, 1.0),
          ((rim + 2) / outerReach).clamp(0.0, 1.0),
          ((rim + coreRef * 0.07) / outerReach).clamp(0.0, 1.0),
          1.0,
        ],
      );
    canvas.drawCircle(center, outerReach, bloom);

    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = coreRef * 0.04
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6)
      ..color = _bright.withValues(alpha: 0.22 * i);
    canvas.drawCircle(center, rim + 1.2, edge);

    final puff = Paint()..style = PaintingStyle.fill;
    const puffs = 120;
    for (var n = 0; n < puffs; n++) {
      final wobble = math.sin(n * 12.9898) * 43758.5453;
      final frac = wobble - wobble.floorToDouble();
      final wobble2 = math.sin(n * 78.233) * 12345.6789;
      final frac2 = wobble2 - wobble2.floorToDouble();

      final angle =
          (n / puffs) * math.pi * 2 + frac * 0.08 + texturePhase * 0.15;
      final outward = 2.0 + frac * coreRef * 0.11;
      final p = Offset(
        center.dx + math.cos(angle) * (rim + outward),
        center.dy + math.sin(angle) * (rim + outward),
      );
      final radius = 2.5 + frac2 * 7.5;
      final alpha = (0.04 + frac * 0.12) * i * smokeBoost;
      final col = frac > 0.55 ? _hot : _mid;

      puff
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2.5 + frac2 * 4.5)
        ..color = col.withValues(alpha: alpha);
      canvas.drawCircle(p, radius, puff);
    }

    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const arcs = 48;
    for (var n = 0; n < arcs; n++) {
      final wobble = math.sin(n * 4.1415) * 9973.0;
      final frac = wobble - wobble.floorToDouble();
      final angle = (n / arcs) * math.pi * 2 + texturePhase * 0.1;
      final r = rim + 1.5 + frac * 8.0;
      final len = 0.08 + frac * 0.18;

      arcPaint
        ..strokeWidth = 2.0 + frac * 4.0
        ..color = _mid.withValues(alpha: (0.04 + frac * 0.10) * i * smokeBoost)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3.0 + frac * 4.0);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: r),
        angle - len / 2,
        len,
        false,
        arcPaint,
      );
    }

    for (var k = 0; k < 4; k++) {
      final a = -math.pi / 2 + k * (math.pi / 2) + texturePhase * 0.02;
      final p = Offset(
        center.dx + math.cos(a) * (rim + 3),
        center.dy + math.sin(a) * (rim + 3),
      );
      puff
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8)
        ..color = _bright.withValues(alpha: 0.12 * i);
      canvas.drawCircle(p, 8.0, puff);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _TexturedGoldRimPainter oldDelegate) {
    return oldDelegate.rimRadius != rimRadius ||
        oldDelegate.intensity != intensity ||
        oldDelegate.bloomExtra != bloomExtra ||
        oldDelegate.texturePhase != texturePhase ||
        oldDelegate.shimmer != shimmer;
  }
}
