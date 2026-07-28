import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Fast connect accent: light appears at an edge, flies once to the button,
/// soft-pulses until [homeIn], then dissolves into the button glow.
///
/// Designed to stay under ~0.7s of motion so it never feels like a wait.
class ConnectingLightOverlay extends StatefulWidget {
  const ConnectingLightOverlay({
    super.key,
    required this.homeIn,
    required this.abort,
    required this.target,
    required this.onSettled,
    required this.onAborted,
  });

  /// VPN ready — finish the pulse and hand off to the lit button.
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
  late final math.Random _rng;

  Duration _lastElapsed = Duration.zero;
  late Offset _start;
  late Offset _mid;
  late Offset _pos;
  double _flightT = 0;
  double _opacity = 0;
  double _coreScale = 0.4;
  double _pulse = 0;
  bool _arrived = false;
  bool _settling = false;
  bool _aborting = false;
  bool _finished = false;
  bool _spawned = false;

  static const double _flightSeconds = 0.55;

  @override
  void initState() {
    super.initState();
    _rng = math.Random();
    _start = Offset.zero;
    _mid = Offset.zero;
    _pos = Offset.zero;
    _ticker = createTicker(_onTick);
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final size = MediaQuery.sizeOf(context);
      _start = _spawnEdge(size);
      _pos = _start;
      final target = widget.target;
      final chord = target - _start;
      final bend = _perp(chord) * (16 + _rng.nextDouble() * 10);
      _mid = Offset.lerp(_start, target, 0.5)! + bend;
      _spawned = true;
      _ticker.start();
    });
  }

  @override
  void didUpdateWidget(covariant ConnectingLightOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_finished && widget.abort && !oldWidget.abort) {
      _aborting = true;
      _settling = false;
    }
    if (!_finished &&
        widget.homeIn &&
        !oldWidget.homeIn &&
        _arrived &&
        !_settling &&
        !_aborting) {
      _settling = true;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    if (_finished || !mounted || !_spawned) {
      return;
    }

    var dt = (elapsed - _lastElapsed).inMicroseconds / 1e6;
    _lastElapsed = elapsed;
    if (dt <= 0 || dt > 0.05) {
      dt = 1 / 60;
    }

    if (_aborting) {
      _opacity = (_opacity - dt * 4.0).clamp(0.0, 1.0);
      if (_opacity <= 0.01) {
        _done(aborted: true);
      } else {
        setState(() {});
      }
      return;
    }

    if (_settling) {
      _opacity = (_opacity - dt * 3.5).clamp(0.0, 1.0);
      _coreScale = (_coreScale + dt * 2.5).clamp(0.0, 2.2);
      if (_opacity <= 0.02) {
        _done(aborted: false);
      } else {
        setState(() {});
      }
      return;
    }

    // Fade in while flying.
    if (_opacity < 1) {
      _opacity = (_opacity + dt * 4.5).clamp(0.0, 1.0);
    }

    if (!_arrived) {
      _flightT = (_flightT + dt / _flightSeconds).clamp(0.0, 1.0);
      final t = Curves.easeInOutCubic.transform(_flightT);
      _pos = _quadBezier(_start, _mid, widget.target, t);
      _coreScale = lerpDouble(0.45, 1.0, t)!;

      if (_flightT >= 1) {
        _arrived = true;
        _pos = widget.target;
        if (widget.homeIn) {
          _settling = true;
        }
      }
    } else {
      // Soft hold at the button while the tunnel comes up.
      _pulse += dt * 3.2;
      _coreScale = 1.0 + 0.08 * math.sin(_pulse);
      _pos = widget.target;
      if (widget.homeIn) {
        _settling = true;
      }
    }

    setState(() {});
  }

  Offset _perp(Offset v) {
    final len = v.distance;
    if (len < 1) {
      return const Offset(0, -1);
    }
    final n = Offset(-v.dy / len, v.dx / len);
    return _rng.nextBool() ? n : -n;
  }

  Offset _quadBezier(Offset a, Offset b, Offset c, double t) {
    final u = 1 - t;
    return a * (u * u) + b * (2 * u * t) + c * (t * t);
  }

  Offset _spawnEdge(Size size) {
    const inset = 24.0;
    // Prefer top/side — reads as “light entering the void”.
    final edge = _rng.nextInt(3);
    switch (edge) {
      case 0:
        return Offset(
          inset + _rng.nextDouble() * (size.width - 2 * inset),
          inset,
        );
      case 1:
        return Offset(
          size.width - inset,
          inset + _rng.nextDouble() * (size.height * 0.45),
        );
      default:
        return Offset(
          inset,
          inset + _rng.nextDouble() * (size.height * 0.45),
        );
    }
  }

  void _done({required bool aborted}) {
    if (_finished) {
      return;
    }
    _finished = true;
    _ticker.stop();
    if (aborted) {
      widget.onAborted();
    } else {
      widget.onSettled();
    }
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _LightPainter(
            pos: _pos,
            opacity: _opacity,
            coreScale: _coreScale,
            settling: _settling,
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
    required this.settling,
  });

  final Offset pos;
  final double opacity;
  final double coreScale;
  final bool settling;

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0.01) {
      return;
    }

    final bloom = settling ? 1.25 : 1.0;
    final layers = <(double, double)>[
      (56 * coreScale * bloom, 0.05 * opacity),
      (30 * coreScale * bloom, 0.1 * opacity),
      (14 * coreScale, 0.28 * opacity),
      (6 * coreScale, 0.65 * opacity),
      (2.4 * coreScale, 0.95 * opacity),
    ];

    for (final (r, a) in layers) {
      canvas.drawCircle(
        pos,
        r,
        Paint()..color = Colors.white.withValues(alpha: a),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LightPainter oldDelegate) {
    return oldDelegate.pos != pos ||
        oldDelegate.opacity != opacity ||
        oldDelegate.coreScale != coreScale ||
        oldDelegate.settling != settling;
  }
}
