import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Drakar connect control: medallion on top, rays + textured gold rim behind.
class DrakarMedallionButton extends StatefulWidget {
  const DrakarMedallionButton({
    super.key,
    required this.connected,
    required this.onTap,
    this.connecting = false,
    this.buttonKey,
    this.diameter = 168,
  });

  final bool connected;
  final bool connecting;
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
  late final AnimationController _spin;
  late final AnimationController _flash;
  late final AnimationController _settle;
  late final AnimationController _extinguish;
  /// True from disconnect FX start until hard reset — avoids a one-frame black flash
  /// when `_extinguish.value` is still 0.
  bool _extinguishingActive = false;

  /// Absolute CCW spin angle (radians), continuous across handoff.
  double _spinAngle = 0;
  double _prevSpinValue = 0;
  /// Extra revolutions to coast through during settle (easeOut).
  static const double _settleCoastTurns = 0.55;
  /// Soft clockwise unwind while dying.
  static const double _extinguishCoastTurns = 0.28;

  // Snapshots at disconnect so the fade does not jump.
  double _extIntensity = 0;
  double _extBloom = 0;
  double _extRaysOpacity = 0;
  double _extRaysScale = 1;
  double _extAngle = 0;
  double _extShimmer = 0;
  double _extTexturePhase = 0;
  double _extMedalScale = 1;

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
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..addListener(_onSpinTick);
    _flash = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    _settle = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    )..addStatusListener(_onSettleStatus);
    _extinguish = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 820),
    )..addStatusListener(_onExtinguishStatus);

    if (widget.connected) {
      _startBreathing();
    } else if (widget.connecting) {
      _beginConnecting();
    }
  }

  @override
  void didUpdateWidget(covariant DrakarMedallionButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    final wasLit = oldWidget.connected || oldWidget.connecting;
    final isLit = widget.connected || widget.connecting;

    if (widget.connecting && !oldWidget.connecting && !widget.connected) {
      _extinguishingActive = false;
      _extinguish.stop();
      _beginConnecting();
    } else if (widget.connected && !oldWidget.connected) {
      _extinguishingActive = false;
      _extinguish.stop();
      _beginSettleToConnected();
    } else if (!isLit && wasLit) {
      _beginExtinguish(fromConnected: oldWidget.connected);
    }
  }

  void _onSpinTick() {
    // Accumulate continuous angle while spinning (handles wrap 1→0).
    var delta = _spin.value - _prevSpinValue;
    if (delta < -0.5) {
      delta += 1.0;
    }
    _prevSpinValue = _spin.value;
    if (_spin.isAnimating) {
      _spinAngle -= delta * math.pi * 2; // negative = CCW on screen
    }
  }

  void _onSettleStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _spin
        ..stop()
        ..value = 0;
      _prevSpinValue = 0;
    }
  }

  void _onExtinguishStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _hardResetFx();
    }
  }

  void _beginConnecting() {
    _extinguishingActive = false;
    _settle
      ..stop()
      ..value = 0;
    _extinguish
      ..stop()
      ..value = 0;
    _stopBreathing();
    _prevSpinValue = _spin.value;
    _startSpin();
    _flash.forward(from: 0);
  }

  void _beginSettleToConnected() {
    // Keep current angle; coast a fraction of a turn while easing to rest.
    _spin.stop();
    _startBreathing();
    _settle.forward(from: 0);
  }

  void _beginExtinguish({required bool fromConnected}) {
    final breath = _sin01(_breath);
    final settleRaw = fromConnected
        ? (_settle.isAnimating ||
                _settle.status == AnimationStatus.completed)
            ? _settle.value
            : 1.0
        : 0.0;
    final settleT = Curves.easeOutCubic.transform(settleRaw);

    final connectIntensity = 0.9;
    final connectedIntensity = 0.55 + 0.45 * breath;
    _extIntensity = fromConnected
        ? ui.lerpDouble(connectIntensity, connectedIntensity, settleT)!
        : connectIntensity;
    _extBloom = fromConnected
        ? ui.lerpDouble(1.0, 0.85 + 0.35 * breath, settleT)!
        : 1.0;
    _extRaysOpacity =
        fromConnected ? settleT * (0.45 + 0.55 * breath) : 0.0;
    _extRaysScale = fromConnected
        ? ui.lerpDouble(0.92, 1.0 + 0.04 * breath, settleT)!
        : 1.0;
    _extMedalScale = fromConnected
        ? ui.lerpDouble(1.0, 1.0 + 0.012 * breath, settleT)!
        : 1.0;
    _extShimmer = fromConnected ? _sin01(_shimmer) : 0.7;
    _extTexturePhase =
        fromConnected ? _shimmer.value * math.pi * 2 : 0.0;

    if (fromConnected &&
        (_settle.isAnimating ||
            _settle.status == AnimationStatus.completed)) {
      _extAngle =
          _spinAngle - settleT * _settleCoastTurns * math.pi * 2;
    } else {
      _extAngle = _spinAngle;
    }

    _spin.stop();
    _flash.stop();
    // Keep breath/shimmer frozen at snapshot — stop so values stay put.
    _breath.stop();
    _shimmer.stop();
    _settle.stop();
    _extinguishingActive = true;
    _extinguish.forward(from: 0);
  }

  void _startBreathing() {
    if (!_breath.isAnimating) {
      _breath.repeat();
    }
    if (!_shimmer.isAnimating) {
      _shimmer.repeat();
    }
  }

  void _stopBreathing() {
    _breath
      ..stop()
      ..value = 0;
    _shimmer
      ..stop()
      ..value = 0;
  }

  void _startSpin() {
    if (!_spin.isAnimating) {
      _spin.repeat();
    }
  }

  void _hardResetFx() {
    _extinguishingActive = false;
    _spin
      ..stop()
      ..value = 0;
    _prevSpinValue = 0;
    _spinAngle = 0;
    _settle
      ..stop()
      ..value = 0;
    _flash
      ..stop()
      ..value = 0;
    _extinguish
      ..stop()
      ..value = 0;
    _extIntensity = 0;
    _extBloom = 0;
    _extRaysOpacity = 0;
    _extRaysScale = 1;
    _extAngle = 0;
    _extShimmer = 0;
    _extTexturePhase = 0;
    _extMedalScale = 1;
    _stopBreathing();
  }

  @override
  void dispose() {
    _spin.removeListener(_onSpinTick);
    _settle.removeStatusListener(_onSettleStatus);
    _extinguish.removeStatusListener(_onExtinguishStatus);
    _breath.dispose();
    _shimmer.dispose();
    _spin.dispose();
    _flash.dispose();
    _settle.dispose();
    _extinguish.dispose();
    super.dispose();
  }

  double _sin01(AnimationController c) =>
      0.5 + 0.5 * math.sin(c.value * math.pi * 2);

  @override
  Widget build(BuildContext context) {
    final raysSize = widget.diameter * 2.35;
    final hitSize = widget.diameter;
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
        child: SizedBox(
          key: widget.buttonKey,
          width: hitSize,
          height: hitSize,
          child: AnimatedBuilder(
            animation: Listenable.merge([
              _breath,
              _shimmer,
              _spin,
              _flash,
              _settle,
              _extinguish,
            ]),
            builder: (context, _) {
              final connected = widget.connected;
              final connecting = widget.connecting && !connected;
              final extinguishing = _extinguishingActive;
              final dying = Curves.easeInCubic.transform(_extinguish.value);
              final alive = 1.0 - dying;
              final lit = connecting || connected || extinguishing;

              // 0 while connecting; ease 0→1 on handoff; 1 if already connected.
              final settleRaw = !connected
                  ? 0.0
                  : (_settle.isAnimating ||
                          _settle.status == AnimationStatus.completed)
                      ? _settle.value
                      : 1.0;
              final settleT = Curves.easeOutCubic.transform(settleRaw);
              final breath = connected ? _sin01(_breath) : 0.0;
              final shimmer = connected ? _sin01(_shimmer) : 0.0;

              // Continuous spin while connecting; coast + ease to rest on settle.
              // On extinguish: soft clockwise unwind from snapshot.
              final double spinAngle;
              if (extinguishing) {
                spinAngle =
                    _extAngle + dying * _extinguishCoastTurns * math.pi * 2;
              } else if (connecting) {
                spinAngle = _spinAngle;
              } else if (connected &&
                  (_settle.isAnimating ||
                      _settle.status == AnimationStatus.completed)) {
                spinAngle =
                    _spinAngle - settleT * _settleCoastTurns * math.pi * 2;
              } else {
                spinAngle = 0.0;
              }

              final texturePhase = extinguishing
                  ? _extTexturePhase
                  : connected
                      ? _shimmer.value * math.pi * 2
                      : 0.0;

              final connectIntensity = 0.9;
              final connectedIntensity = 0.55 + 0.45 * breath;
              double intensity;
              double bloomExtra;
              double raysOpacity;
              double raysScale;
              double medalScale;
              double smokeShimmer;

              if (extinguishing) {
                // Soft die: intensity falls a bit faster than rays.
                final glowAlive = math.pow(alive, 1.15).toDouble();
                final raysAlive = math.pow(alive, 0.85).toDouble();
                intensity = _extIntensity * glowAlive;
                bloomExtra = _extBloom * (0.55 + 0.45 * glowAlive);
                raysOpacity = _extRaysOpacity * raysAlive;
                raysScale = ui.lerpDouble(_extRaysScale, 0.88, dying)!;
                medalScale = ui.lerpDouble(_extMedalScale, 1.0, dying)!;
                smokeShimmer = _extShimmer * alive;
              } else if (connecting) {
                intensity = connectIntensity;
                bloomExtra = 1.0;
                raysOpacity = 0.0;
                raysScale = 1.0;
                medalScale = 1.0;
                smokeShimmer = 0.7;
              } else if (connected) {
                intensity = ui.lerpDouble(
                  connectIntensity,
                  connectedIntensity,
                  settleT,
                )!;
                bloomExtra =
                    ui.lerpDouble(1.0, 0.85 + 0.35 * breath, settleT)!;
                raysOpacity = settleT * (0.45 + 0.55 * breath);
                raysScale =
                    ui.lerpDouble(0.92, 1.0 + 0.04 * breath, settleT)!;
                medalScale =
                    ui.lerpDouble(1.0, 1.0 + 0.012 * breath, settleT)!;
                smokeShimmer = shimmer;
              } else {
                intensity = 0.0;
                bloomExtra = 0.0;
                raysOpacity = 0.0;
                raysScale = 1.0;
                medalScale = 1.0;
                smokeShimmer = 0.0;
              }

              final flashT = _flash.value;
              final showFlash = flashT > 0 && flashT < 1;

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
                        opacity: raysOpacity.clamp(0.0, 1.0),
                        child: Transform.scale(
                          scale: raysScale,
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
                        opacity: extinguishing
                            ? alive.clamp(0.0, 1.0)
                            : (lit && intensity > 0.01 ? 1.0 : 0.0),
                        child: Transform.rotate(
                          angle: spinAngle,
                          child: CustomPaint(
                            size: Size.square(glowSize),
                            painter: _TexturedGoldRimPainter(
                              rimRadius: rimRadius,
                              intensity: intensity,
                              bloomExtra: bloomExtra,
                              texturePhase: texturePhase,
                              shimmer: smokeShimmer,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Press scale only on the medallion — glow/rays stay put.
                  AnimatedScale(
                    scale: _pressed ? 0.94 : 1.0,
                    duration: const Duration(milliseconds: 90),
                    curve: Curves.easeOutCubic,
                    child: Transform.scale(
                      scale: medalScale,
                      child: Image.asset(
                        DrakarMedallionButton.medallionAsset,
                        width: hitSize,
                        height: hitSize,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                      ),
                    ),
                  ),
                  if (showFlash)
                    Positioned(
                      left: (hitSize - glowSize) / 2,
                      top: (hitSize - glowSize) / 2,
                      width: glowSize,
                      height: glowSize,
                      child: IgnorePointer(
                        child: CustomPaint(
                          size: Size.square(glowSize),
                          painter: _IgnitionFlashPainter(
                            progress: flashT,
                            rimRadius: rimRadius,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Brief gold-white burst from the medallion center outward.
class _IgnitionFlashPainter extends CustomPainter {
  _IgnitionFlashPainter({
    required this.progress,
    required this.rimRadius,
  });

  final double progress;
  final double rimRadius;

  static const Color _core = Color(0xFFFFF4D2);
  static const Color _hot = Color(0xFFFFD27A);
  static const Color _gold = Color(0xFFD4A017);
  static const Color _ember = Color(0xFF8A5818);

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0.001) return;

    final center = Offset(size.width / 2, size.height / 2);
    // Ease: snap bright, then soft decay.
    final rise = (progress / 0.18).clamp(0.0, 1.0);
    final fall = progress < 0.18
        ? 1.0
        : (1.0 - Curves.easeOutCubic.transform((progress - 0.18) / 0.82));
    final opacity = rise * fall;
    if (opacity <= 0.01) return;

    // Expanding radius: starts inside disc, blows past the rim.
    final expand = Curves.easeOutCubic.transform(progress);
    final reach = rimRadius * (0.35 + 1.55 * expand);

    // Soft outer wash.
    canvas.drawCircle(
      center,
      reach * 1.15,
      Paint()
        ..color = _ember.withValues(alpha: 0.22 * opacity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 28),
    );

    // Main gold bloom.
    canvas.drawCircle(
      center,
      reach,
      Paint()
        ..shader = ui.Gradient.radial(
          center,
          reach,
          [
            _core.withValues(alpha: 0.95 * opacity),
            _hot.withValues(alpha: 0.70 * opacity),
            _gold.withValues(alpha: 0.38 * opacity),
            _ember.withValues(alpha: 0.12 * opacity),
            _ember.withValues(alpha: 0.0),
          ],
          const [0.0, 0.18, 0.42, 0.72, 1.0],
        ),
    );

    // Hot core punch.
    final coreR = rimRadius * (0.12 + 0.22 * (1.0 - expand * 0.65));
    canvas.drawCircle(
      center,
      coreR,
      Paint()
        ..shader = ui.Gradient.radial(
          center,
          coreR,
          [
            Colors.white.withValues(alpha: 0.95 * opacity),
            _core.withValues(alpha: 0.55 * opacity),
            _hot.withValues(alpha: 0.0),
          ],
          const [0.0, 0.45, 1.0],
        ),
    );

    // Thin expanding shock ring.
    final ringR = rimRadius * (0.55 + 1.1 * expand);
    canvas.drawCircle(
      center,
      ringR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5 + 6.0 * (1.0 - expand)
        ..color = _hot.withValues(alpha: 0.45 * opacity * (1.0 - expand * 0.5))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
  }

  @override
  bool shouldRepaint(covariant _IgnitionFlashPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.rimRadius != rimRadius;
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

  static const Color _deep = Color(0xFF3A1E01);
  static const Color _mid = Color(0xFF8A5818);
  static const Color _bright = Color(0xFFB07412);
  static const Color _hot = Color(0xFF9A6414);

  @override
  void paint(Canvas canvas, Size size) {
    if (intensity <= 0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final i = intensity.clamp(0.0, 1.0);
    final rim = rimRadius;
    final smokeBoost = 0.85 + 0.15 * shimmer;
    final medalDiameter =
        2 * rim / DrakarMedallionButton.contentRadiusFactor;
    final coreRef = medalDiameter * 1.65;

    canvas.save();
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addOval(Rect.fromCircle(center: center, radius: rim - 0.5));
    canvas.clipPath(outside);

    final veilReach = size.shortestSide / 2;
    final veilBreath = 0.7 + 0.3 * i;
    final veil = Paint()
      ..shader = ui.Gradient.radial(
        center,
        veilReach,
        [
          _mid.withValues(alpha: 0.0),
          _mid.withValues(alpha: 0.0),
          _mid.withValues(alpha: 0.10 * i * veilBreath),
          _deep.withValues(alpha: 0.042 * i * veilBreath),
          _deep.withValues(alpha: 0.022 * i * veilBreath),
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

    final outerReach = rim + coreRef * 0.16 * bloomExtra;

    final bloom = Paint()
      ..shader = ui.Gradient.radial(
        center,
        outerReach,
        [
          _mid.withValues(alpha: 0.0),
          _bright.withValues(alpha: 0.0),
          _bright.withValues(alpha: 0.34 * i),
          _mid.withValues(alpha: 0.24 * i),
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
      ..color = _bright.withValues(alpha: 0.26 * i);
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
