import 'dart:async';

import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BratanVPN',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        colorScheme: const ColorScheme.dark(
          primary: Colors.white,
          onPrimary: Colors.black,
          surface: Colors.black,
          onSurface: Colors.white,
        ),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const Color _background = Colors.black;

  bool _connected = false;
  Duration _session = Duration.zero;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _toggleConnection() {
    setState(() {
      _connected = !_connected;
      if (_connected) {
        _session = Duration.zero;
        _timer?.cancel();
        _timer = Timer.periodic(const Duration(seconds: 1), (_) {
          setState(() => _session += const Duration(seconds: 1));
        });
      } else {
        _timer?.cancel();
        _timer = null;
        _session = Duration.zero;
      }
    });
  }

  String get _sessionLabel {
    final hours = _session.inHours.toString().padLeft(2, '0');
    final minutes = (_session.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (_session.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final buttonFill = _connected ? Colors.white : _background;
    final iconColor = _connected ? Colors.black : Colors.white;
    final label = _connected ? 'Подключено' : 'Подключиться';

    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'BRATANVPN',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 3,
                    ),
                  ),
                  const SizedBox(height: 36),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: _toggleConnection,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        width: 148,
                        height: 148,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: buttonFill,
                          border: _connected
                              ? null
                              : Border.all(
                                  color: Colors.white.withValues(alpha: 0.35),
                                  width: 1.5,
                                ),
                          boxShadow: _connected
                              ? [
                                  BoxShadow(
                                    color: Colors.white.withValues(alpha: 0.45),
                                    blurRadius: 24,
                                    spreadRadius: 4,
                                  ),
                                  BoxShadow(
                                    color: Colors.white.withValues(alpha: 0.2),
                                    blurRadius: 44,
                                    spreadRadius: 10,
                                  ),
                                ]
                              : null,
                        ),
                        child: Icon(
                          Icons.power_settings_new,
                          size: 56,
                          color: iconColor,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _sessionLabel,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            const Positioned(
              left: 0,
              right: 0,
              bottom: 28,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('🇫🇷', style: TextStyle(fontSize: 28)),
                  SizedBox(height: 6),
                  Text(
                    'Франция',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
