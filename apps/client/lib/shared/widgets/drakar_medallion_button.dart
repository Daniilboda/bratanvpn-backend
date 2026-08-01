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
    // Glow canvas = medallion size; rim is drawn at the real content edge.
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
                // Rim glow — same box as medallion; paints only outside the disc.
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _pulse,
                      builder: (context, _) {
                        final pulse = widget.connected ? _pulse.value : 0.0;
                        return AnimatedOpacity(
                          opacity: widget.connected ? 1.0 : 0.38,
                          duration: const Duration(milliseconds: 320),
                          curve: Curves.easeOutCubic,
                          child: CustomPaint(
                            painter: _TexturedGoldRimPainter(
                              rimRadius: rimRadius,
                              intensity: widget.connected
                                  ? 0.85 + 0.15 * pulse
                                  : 0.5,
                              bloomExtra: widget.connected
                                  ? 1.0 + 0.12 * pulse
                                  : 0.7,
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

  static const Color _deep = Color(0xFF6B4A12);
  static const Color _mid = Color(0xFFC9A227);
  static const Color _bright = Color(0xFFF0D878);
  static const Color _hot = Color(0xFFFFF3C4);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final i = intensity.clamp(0.0, 1.0);
    final rim = rimRadius;

    // Clip: everything inside the medallion disc is discarded —
    // glow lives only outside the stone edge.
    canvas.save();
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addOval(Rect.fromCircle(center: center, radius: rim - 0.5));
    canvas.clipPath(outside);

    final outerReach = rim + size.shortestSide * 0.09 * bloomExtra;

    // Soft bloom radiating from the rim outward.
    final bloom = Paint()
      ..shader = ui.Gradient.radial(
        center,
        outerReach,
        [
          _mid.withValues(alpha: 0.0),
          _bright.withValues(alpha: 0.0),
          _bright.withValues(alpha: 0.55 * i),
          _mid.withValues(alpha: 0.28 * i),
          _deep.withValues(alpha: 0.0),
        ],
        [
          0.0,
          (rim / outerReach).clamp(0.0, 1.0),
          ((rim + 2) / outerReach).clamp(0.0, 1.0),
          ((rim + size.shortestSide * 0.04) / outerReach).clamp(0.0, 1.0),
          1.0,
        ],
      );
    canvas.drawCircle(center, outerReach, bloom);

    // Tight metallic rim line sitting on the edge.
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.8)
      ..color = _hot.withValues(alpha: 0.7 * i);
    canvas.drawCircle(center, rim + 0.8, edge);

    final edgeSoft = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.shortestSide * 0.035
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5)
      ..color = _mid.withValues(alpha: 0.45 * i);
    canvas.drawCircle(center, rim + 1.5, edgeSoft);

    // Hammered-gold flecks along the rim, outward only.
    final fleckPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const flecks = 88;
    for (var n = 0; n < flecks; n++) {
      final angle = (n / flecks) * math.pi * 2;
      final wobble = math.sin(n * 12.9898) * 43758.5453;
      final frac = wobble - wobble.floorToDouble();
      final r = rim + 1.0 + frac * 3.5;
      final len = 0.03 + frac * 0.08;
      final alpha = (0.2 + frac * 0.5) * i;
      final warm = frac > 0.6;

      fleckPaint
        ..strokeWidth = 1.0 + frac * 2.0
        ..color = (warm ? _hot : _mid).withValues(alpha: alpha)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 0.5 + frac * 1.4);

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: r),
        angle - len / 2,
        len,
        false,
        fleckPaint,
      );
    }

    // Sparks at the four diamond bosses.
    final spark = Paint()..style = PaintingStyle.fill;
    for (var k = 0; k < 4; k++) {
      final a = -math.pi / 2 + k * (math.pi / 2);
      final p = Offset(
        center.dx + math.cos(a) * (rim + 1),
        center.dy + math.sin(a) * (rim + 1),
      );
      spark
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3)
        ..color = _hot.withValues(alpha: 0.6 * i);
      canvas.drawCircle(p, 3.2, spark);
      spark
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5)
        ..color = _bright.withValues(alpha: 0.25 * i);
      canvas.drawCircle(p, 6.0, spark);
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
