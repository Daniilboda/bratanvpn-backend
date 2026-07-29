import 'dart:async' show scheduleMicrotask;
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Soft spark that ignites at [target] (button center) and grows.
/// When [homeIn] becomes true, hands off to the lit button immediately.
class ConnectingLightOverlay extends StatefulWidget {
  const ConnectingLightOverlay({
    super.key,
    required this.homeIn,
    required this.abort,
    required this.target,
    required this.onSettled,
    required this.onAborted,
  });

  /// Android connect is faster than Windows; wait at least this long before
  /// [homeIn] so the pulse matches the Windows feel (~grow + breath at peak).
  static const Duration androidMinPulse = Duration(milliseconds: 1700);

  final bool homeIn;
  final bool abort;
  final Offset target;
  final VoidCallback onSettled;
  final VoidCallback onAborted;

  @override
  State<ConnectingLightOverlay> createState() => _ConnectingLightOverlayState();
}

class _ConnectingLightOverlayState extends State<ConnectingLightOverlay>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;

  Duration _lastElapsed = Duration.zero;
  double _opacity = 0;
  double _baseScale = 0.4;
  double _displayScale = 0.4;
  double _growT = 0;
  double _breath = 0;
  double _finishFromScale = 1.0;
  bool _finishing = false;
  bool _aborting = false;
  bool _finished = false;

  /// Visible ignition: starts readable, grows hard toward the button edge.
  static const double _growStart = 0.42;
  static const double _growCap = 1.05;
  static const double _growSeconds = 0.85;
  static const double _finishSeconds = 0.2;

  @override
  void initState() {
    super.initState();
    _baseScale = _growStart;
    _displayScale = _growStart;
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void didUpdateWidget(covariant ConnectingLightOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_finished && widget.abort && !oldWidget.abort) {
      _aborting = true;
      _finishing = false;
    }
    if (!_finished &&
        widget.homeIn &&
        !oldWidget.homeIn &&
        !_aborting &&
        !_finishing) {
      _beginFinish();
    }
  }

  void _beginFinish() {
    _finishing = true;
    _finishFromScale = _displayScale;
    _growT = 0;
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    if (_finished || !mounted) {
      return;
    }

    var dt = (elapsed - _lastElapsed).inMicroseconds / 1e6;
    _lastElapsed = elapsed;
    if (dt <= 0 || dt > 0.05) {
      dt = 1 / 60;
    }

    if (_aborting) {
      _opacity = (_opacity - dt * 4.5).clamp(0.0, 1.0);
      _displayScale = (_displayScale - dt * 1.8).clamp(0.0, 3.0);
      if (_opacity <= 0.01) {
        _done(aborted: true);
      } else {
        setState(() {});
      }
      return;
    }

    // Snap in bright — no slow fade that hides the spark.
    if (_opacity < 1) {
      _opacity = (_opacity + dt * 10.0).clamp(0.0, 1.0);
    }

    if (_finishing || widget.homeIn) {
      if (!_finishing) {
        _beginFinish();
      }
      _growT = (_growT + dt / _finishSeconds).clamp(0.0, 1.0);
      final u = Curves.easeOutCubic.transform(_growT);
      _displayScale = lerpDouble(_finishFromScale, 1.55, u)!;
      if (_growT >= 1) {
        _done(aborted: false);
        return;
      }
      setState(() {});
      return;
    }

    // Trying to catch fire: grow + restless breath.
    _growT = (_growT + dt / _growSeconds).clamp(0.0, 1.0);
    final u = Curves.easeOutCubic.transform(_growT);
    _baseScale = lerpDouble(_growStart, _growCap, u)!;
    _breath += dt * 5.5;
    // Stronger pulse early, settles a bit as it grows — “trying to ignite”.
    final struggle = 0.18 * (1.0 - 0.45 * u);
    final breath = 1.0 + struggle * math.sin(_breath);
    _displayScale = _baseScale * breath;
    setState(() {});
  }

  void _done({required bool aborted}) {
    if (_finished) {
      return;
    }
    _finished = true;
    _ticker.stop();
    final callback = aborted ? widget.onAborted : widget.onSettled;
    scheduleMicrotask(callback);
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _LightPainter(
            pos: widget.target,
            opacity: _opacity,
            coreScale: _displayScale,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _LightPainter extends CustomPainter {
  _LightPainter({
    required this.pos,
    required this.opacity,
    required this.coreScale,
  });

  final Offset pos;
  final double opacity;
  final double coreScale;

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0.01) {
      return;
    }

    // Cover the full 148px button (radius 74) at the end of ignition.
    final glowR = 68.0 * coreScale;
    final coreR = 15.0 * coreScale;

    // Dark cushion so white light pops on the white icon.
    canvas.drawCircle(
      pos,
      glowR * 0.55,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.5 * opacity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16),
    );

    // Wide outer halo — stronger bloom around the button.
    canvas.drawCircle(
      pos,
      glowR * 1.15,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.28 * opacity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 28),
    );

    canvas.drawCircle(
      pos,
      glowR * 0.85,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.55 * opacity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20),
    );

    canvas.drawCircle(
      pos,
      glowR,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: 0.9 * opacity),
            Colors.white.withValues(alpha: 0.55 * opacity),
            Colors.white.withValues(alpha: 0.22 * opacity),
            Colors.white.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.3, 0.58, 1.0],
        ).createShader(Rect.fromCircle(center: pos, radius: glowR)),
    );

    canvas.drawCircle(
      pos,
      coreR,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: opacity),
            Colors.white.withValues(alpha: 0.7 * opacity),
            Colors.white.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.45, 1.0],
        ).createShader(Rect.fromCircle(center: pos, radius: coreR)),
    );
  }

  @override
  bool shouldRepaint(covariant _LightPainter oldDelegate) {
    return oldDelegate.pos != pos ||
        oldDelegate.opacity != opacity ||
        oldDelegate.coreScale != coreScale;
  }
}
