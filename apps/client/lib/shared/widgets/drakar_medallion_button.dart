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
    with SingleTickerProviderStateMixin {
  bool _pressed = false;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    if (widget.connected) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant DrakarMedallionButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.connected && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!widget.connected && _pulse.isAnimating) {
      _pulse
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final raysSize = widget.diameter * 2.35;
    final hitSize = widget.diameter;
    final glowSize = hitSize * 1.65; // холст свечения (чтобы дым не обрезался)
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
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Positioned(
                  left: (hitSize - raysSize) / 2,
                  top: (hitSize - raysSize) / 2,
                  width: raysSize,
                  height: raysSize,
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: widget.connected ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOutCubic,
                      child: Image.asset(
                        DrakarMedallionButton.raysAsset,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
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
                    child: AnimatedBuilder(
                      animation: _pulse,
                      builder: (context, _) {
                        final pulse = widget.connected ? _pulse.value : 0.0;
                        return AnimatedOpacity(
                          opacity: widget.connected ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 320),
                          curve: Curves.easeOutCubic,
                          child: CustomPaint(
                            size: Size.square(glowSize),
                            painter: _TexturedGoldRimPainter(
                              rimRadius: rimRadius,
                              intensity: widget.connected
                                  ? 0.9 + 0.1 * pulse
                                  : 0.0,
                              bloomExtra: widget.connected
                                  ? 1.0 + 0.08 * pulse
                                  : 0.0,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                Image.asset(
                  DrakarMedallionButton.medallionAsset,
                  width: hitSize,
                  height: hitSize,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                ),
              ],
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
  });

  final double rimRadius;
  final double intensity;
  final double bloomExtra;

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

    canvas.save();
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addOval(Rect.fromCircle(center: center, radius: rim - 0.5));
    canvas.clipPath(outside);

    final outerReach = rim + size.shortestSide * 0.16 * bloomExtra; // ширина дыма

    // Базовый ореол.
    final bloom = Paint()
      ..shader = ui.Gradient.radial(
        center,
        outerReach,
        [
          _mid.withValues(alpha: 0.0),
          _bright.withValues(alpha: 0.0),
          _bright.withValues(alpha: 0.28 * i), // сила у края
          _mid.withValues(alpha: 0.20 * i),
          _deep.withValues(alpha: 0.0),
        ],
        [
          0.0,
          (rim / outerReach).clamp(0.0, 1.0),
          ((rim + 2) / outerReach).clamp(0.0, 1.0),
          ((rim + size.shortestSide * 0.07) / outerReach).clamp(0.0, 1.0),
          1.0,
        ],
      );
    canvas.drawCircle(center, outerReach, bloom);

    // Мягкая кромка.
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.shortestSide * 0.04
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6)
      ..color = _bright.withValues(alpha: 0.22 * i); // сила кромки
    canvas.drawCircle(center, rim + 1.2, edge);

    // Дымные «облачка» по ободу — основная текстура.
    final puff = Paint()..style = PaintingStyle.fill;
    const puffs = 120; // густота дыма
    for (var n = 0; n < puffs; n++) {
      final wobble = math.sin(n * 12.9898) * 43758.5453;
      final frac = wobble - wobble.floorToDouble();
      final wobble2 = math.sin(n * 78.233) * 12345.6789;
      final frac2 = wobble2 - wobble2.floorToDouble();

      final angle = (n / puffs) * math.pi * 2 + frac * 0.08;
      final outward = 2.0 + frac * size.shortestSide * 0.11; // как далеко от обода
      final p = Offset(
        center.dx + math.cos(angle) * (rim + outward),
        center.dy + math.sin(angle) * (rim + outward),
      );
      final radius = 2.5 + frac2 * 7.5; // размер облачка
      final alpha = (0.04 + frac * 0.12) * i; // сила текстуры
      final col = frac > 0.55 ? _hot : _mid;

      puff
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2.5 + frac2 * 4.5)
        ..color = col.withValues(alpha: alpha);
      canvas.drawCircle(p, radius, puff);
    }

    // Длинные дымные дуги (неровный слой).
    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const arcs = 48; // густота дуг
    for (var n = 0; n < arcs; n++) {
      final wobble = math.sin(n * 4.1415) * 9973.0;
      final frac = wobble - wobble.floorToDouble();
      final angle = (n / arcs) * math.pi * 2;
      final r = rim + 1.5 + frac * 8.0;
      final len = 0.08 + frac * 0.18;

      arcPaint
        ..strokeWidth = 2.0 + frac * 4.0
        ..color = _mid.withValues(alpha: (0.04 + frac * 0.10) * i)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3.0 + frac * 4.0);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: r),
        angle - len / 2,
        len,
        false,
        arcPaint,
      );
    }

    // Чуть плотнее у ромбов 12/3/6/9 (как на рефе).
    for (var k = 0; k < 4; k++) {
      final a = -math.pi / 2 + k * (math.pi / 2);
      final p = Offset(
        center.dx + math.cos(a) * (rim + 3),
        center.dy + math.sin(a) * (rim + 3),
      );
      puff
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8)
        ..color = _bright.withValues(alpha: 0.12 * i); // сила у ромбов
      canvas.drawCircle(p, 8.0, puff);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _TexturedGoldRimPainter oldDelegate) {
    return oldDelegate.rimRadius != rimRadius ||
        oldDelegate.intensity != intensity ||
        oldDelegate.bloomExtra != bloomExtra;
  }
}
