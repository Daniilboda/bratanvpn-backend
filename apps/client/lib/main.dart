import 'dart:async';

import 'package:flutter/material.dart';

import 'package:client/services/activation_api.dart';
import 'package:client/services/api_config.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.activationApi});

  final ActivationApi? activationApi;

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
      home: HomePage(activationApi: activationApi ?? ActivationApi()),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.activationApi});

  final ActivationApi activationApi;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const Color _background = Colors.black;

  bool _keyActivated = false;
  bool _connected = false;
  String? _vpnIp;
  Duration _session = Duration.zero;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _onPowerPressed() async {
    if (_connected) {
      _setConnected(false);
      return;
    }

    if (!_keyActivated) {
      final result = await _showAccessKeyDialog();
      if (!mounted || result == null) {
        return;
      }
      setState(() {
        _keyActivated = true;
        _vpnIp = result.vpnIp;
      });
    }

    _setConnected(true);
  }

  Future<ActivationSuccess?> _showAccessKeyDialog() {
    return showDialog<ActivationSuccess>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return _AccessKeyDialog(
          activationApi: widget.activationApi,
        );
      },
    );
  }

  void _setConnected(bool connected) {
    setState(() {
      _connected = connected;
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
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                onPressed: () {
                  // Экран настроек добавим позже.
                },
                icon: const Icon(
                  Icons.settings,
                  color: Colors.white,
                  size: 26,
                ),
              ),
            ),
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
                      onTap: _onPowerPressed,
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

class _AccessKeyDialog extends StatefulWidget {
  const _AccessKeyDialog({required this.activationApi});

  final ActivationApi activationApi;

  @override
  State<_AccessKeyDialog> createState() => _AccessKeyDialogState();
}

class _AccessKeyDialogState extends State<_AccessKeyDialog> {
  final _controller = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final accessKey = _controller.text.trim();
    if (accessKey.isEmpty || _loading) {
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await widget.activationApi.activate(
        accessKey: accessKey,
        deviceId: stubDeviceId,
        vpnPublicKey: generateStubVpnPublicKey(),
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(result);
    } on ActivationException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = error.userMessage;
      });
    } on Exception {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = 'Проверьте подключение к интернету.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.black,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.35)),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Введите ключ доступа',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _controller,
              autofocus: true,
              enabled: !_loading,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                letterSpacing: 1,
              ),
              cursorColor: Colors.white,
              decoration: InputDecoration(
                hintText: 'BRTN-XXXX-XXXX-XXXX',
                hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.35),
                  letterSpacing: 1,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: Colors.white.withValues(alpha: 0.35),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Colors.white),
                ),
                disabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: Colors.white.withValues(alpha: 0.2),
                  ),
                ),
              ),
              onSubmitted: (_) => _submit(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFFFF6B6B),
                  fontSize: 13,
                ),
              ),
            ],
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: _loading
                        ? null
                        : () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(
                      'Отмена',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextButton(
                    onPressed: _loading ? null : _submit,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: _loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Подключиться',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
