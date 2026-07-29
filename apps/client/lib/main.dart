import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'package:client/platform/desktop_shell.dart';
import 'package:client/services/access_check_api.dart';
import 'package:client/services/activation_api.dart';
import 'package:client/services/amnezia_config_builder.dart';
import 'package:client/services/secure_vault.dart';
import 'package:client/services/vpn_config_api.dart';
import 'package:client/services/vpn_session.dart';
import 'package:client/services/vpn_tunnel.dart';
import 'package:client/services/vpn_tunnel_factory.dart';
import 'package:client/shared/widgets/connecting_light_overlay.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  DesktopShell? desktopShell;
  if (!kIsWeb && Platform.isWindows) {
    desktopShell = DesktopShell();
    await desktopShell.init();
  }

  runApp(MyApp(desktopShell: desktopShell));
}

class MyApp extends StatelessWidget {
  const MyApp({
    super.key,
    this.activationApi,
    this.vpnConfigApi,
    this.accessCheckApi,
    this.secureVault,
    this.vpnTunnel,
    this.desktopShell,
  });

  final ActivationApi? activationApi;
  final VpnConfigApi? vpnConfigApi;
  final AccessCheckApi? accessCheckApi;
  final SecureVault? secureVault;
  final VpnTunnel? vpnTunnel;
  final DesktopShell? desktopShell;

  @override
  Widget build(BuildContext context) {
    final vault = secureVault ?? SecureVault();
    final tunnel = vpnTunnel ?? createVpnTunnel();

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
      home: HomePage(
        activationApi: activationApi ?? ActivationApi(),
        vpnConfigApi: vpnConfigApi ?? VpnConfigApi(),
        accessCheckApi: accessCheckApi ?? AccessCheckApi(),
        secureVault: vault,
        vpnSession: VpnSession(vault: vault, tunnel: tunnel),
        desktopShell: desktopShell,
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.activationApi,
    required this.vpnConfigApi,
    required this.accessCheckApi,
    required this.secureVault,
    required this.vpnSession,
    this.desktopShell,
  });

  final ActivationApi activationApi;
  final VpnConfigApi vpnConfigApi;
  final AccessCheckApi accessCheckApi;
  final SecureVault secureVault;
  final VpnSession vpnSession;
  final DesktopShell? desktopShell;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const Color _background = Colors.black;
  static const Duration _accessCheckPeriod = Duration(minutes: 15);
  static const Duration _tunnelHealthPeriod = Duration(seconds: 5);

  bool _ready = false;
  bool _keyActivated = false;
  bool _connected = false;
  bool _checkingAccess = false;
  bool _accessPollInFlight = false;
  bool _tunnelHealthInFlight = false;
  bool _connectLightActive = false;
  bool _connectLightHomeIn = false;
  bool _connectLightAbort = false;
  String? _pendingAbortMessage;
  Offset _powerButtonCenter = Offset.zero;
  final GlobalKey _powerButtonKey = GlobalKey();
  final GlobalKey _homeStackKey = GlobalKey();
  Duration _session = Duration.zero;
  Timer? _timer;
  Timer? _accessPollTimer;
  Timer? _tunnelHealthTimer;

  @override
  void initState() {
    super.initState();
    widget.desktopShell?.beforeQuit = _onBeforeQuit;
    _restoreActivation();
  }

  Future<void> _onBeforeQuit() async {
    try {
      await widget.vpnSession.disconnect();
    } on Object {
      // Best-effort stop on exit.
    }
    if (!mounted) {
      return;
    }
    _stopAccessPolling();
    _stopTunnelHealthPolling();
    _timer?.cancel();
    _timer = null;
    setState(() {
      _connected = false;
      _session = Duration.zero;
    });
  }

  Future<void> _restoreActivation() async {
    final activated = await widget.secureVault.isActivated();

    if (!mounted) {
      return;
    }

    setState(() {
      _keyActivated = activated;
      _ready = true;
    });

    if (activated) {
      final ok = await _checkAccess();
      if (mounted && ok) {
        _startAccessPolling();
      }
    }
  }

  void _startAccessPolling() {
    _accessPollTimer?.cancel();
    _accessPollTimer = Timer.periodic(_accessCheckPeriod, (_) {
      unawaited(_pollAccess());
    });
  }

  void _stopAccessPolling() {
    _accessPollTimer?.cancel();
    _accessPollTimer = null;
  }

  void _startTunnelHealthPolling() {
    _tunnelHealthTimer?.cancel();
    _tunnelHealthTimer = Timer.periodic(_tunnelHealthPeriod, (_) {
      unawaited(_pollTunnelHealth());
    });
  }

  void _stopTunnelHealthPolling() {
    _tunnelHealthTimer?.cancel();
    _tunnelHealthTimer = null;
  }

  Future<void> _pollTunnelHealth() async {
    if (!_connected || _tunnelHealthInFlight || !mounted) {
      return;
    }
    _tunnelHealthInFlight = true;
    try {
      final running = await widget.vpnSession.isRunning();
      if (!mounted || !_connected) {
        return;
      }
      if (!running) {
        await _applyTunnelDropped();
      }
    } on Object {
      // Ignore transient query errors; next tick will retry.
    } finally {
      _tunnelHealthInFlight = false;
    }
  }

  Future<void> _applyTunnelDropped() async {
    _stopTunnelHealthPolling();
    try {
      await widget.vpnSession.disconnect();
    } on Object {
      // Best-effort cleanup of a dead/orphan service.
    }
    if (!mounted) {
      return;
    }
    _setConnected(false);
  }

  Future<void> _pollAccess() async {
    if (!_keyActivated || _accessPollInFlight || !mounted) {
      return;
    }
    _accessPollInFlight = true;
    try {
      await _checkAccess();
    } finally {
      _accessPollInFlight = false;
    }
  }

  Future<bool> _checkAccess() async {
    final accessKey = await widget.secureVault.readAccessKey();
    final deviceId = await widget.secureVault.getOrCreateDeviceId();

    if (accessKey == null || accessKey.isEmpty) {
      if (_keyActivated) {
        await _applyAccessBlocked();
      }
      return false;
    }

    try {
      final status = await widget.accessCheckApi.check(
        accessKey: accessKey,
        deviceId: deviceId,
      );

      if (status == AccessCheckStatus.valid) {
        return true;
      }

      await _applyAccessBlocked();
      return false;
    } on AccessCheckException {
      // Network / API errors: keep session; do not show status text on home.
      return false;
    }
  }

  Future<void> _applyAccessBlocked() async {
    try {
      await widget.vpnSession.disconnect();
    } on Object {
      // Best-effort stop.
    }
    await widget.secureVault.clearAccessSession();
    if (!mounted) {
      return;
    }
    _stopAccessPolling();
    _stopTunnelHealthPolling();
    _timer?.cancel();
    _timer = null;
    setState(() {
      _keyActivated = false;
      _connected = false;
      _session = Duration.zero;
    });
  }

  @override
  void dispose() {
    if (widget.desktopShell?.beforeQuit == _onBeforeQuit) {
      widget.desktopShell?.beforeQuit = null;
    }
    _stopAccessPolling();
    _stopTunnelHealthPolling();
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _onPowerPressed() async {
    if (!_ready || _checkingAccess) {
      return;
    }

    if (_connected) {
      setState(() => _checkingAccess = true);
      try {
        await widget.vpnSession.disconnect();
        if (!mounted) {
          return;
        }
        _setConnected(false);
      } on VpnTunnelException {
        // Tunnel stop failed: UI already reflects disconnect attempt.
      } finally {
        if (mounted) {
          setState(() => _checkingAccess = false);
        }
      }
      return;
    }

    if (!_keyActivated) {
      final result = await _showAccessKeyDialog();
      if (!mounted || result == null) {
        return;
      }
      setState(() => _keyActivated = true);
      _startAccessPolling();
      await _startTunnelAndConnect();
      return;
    }

    setState(() => _checkingAccess = true);
    final allowed = await _checkAccess();
    if (!mounted) {
      return;
    }
    if (!allowed) {
      setState(() => _checkingAccess = false);
      return;
    }

    await _startTunnelAndConnect();
  }

  Future<void> _startTunnelAndConnect() async {
    _updatePowerButtonCenter();
    // Immediate feedback: spark ignites at the button center.
    setState(() {
      _checkingAccess = true;
      _connectLightActive = true;
      _connectLightHomeIn = false;
      _connectLightAbort = false;
    });
    try {
      await widget.vpnSession.connect();
      if (!mounted) {
        return;
      }
      _updatePowerButtonCenter();
      // Spark flares into the lit button.
      setState(() => _connectLightHomeIn = true);
    } on AmneziaConfigException catch (error) {
      if (mounted) {
        _abortConnectLight(error.userMessage);
      }
    } on VpnTunnelException catch (error) {
      if (mounted) {
        _abortConnectLight(error.userMessage);
      }
    } on Exception {
      if (mounted) {
        _abortConnectLight('Не удалось запустить VPN.');
      }
    }
  }

  void _abortConnectLight(String message) {
    setState(() {
      _connectLightAbort = true;
      _connectLightHomeIn = false;
    });
    _pendingAbortMessage = message;
  }

  void _updatePowerButtonCenter() {
    final box =
        _powerButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) {
      return;
    }
    final stackBox =
        _homeStackKey.currentContext?.findRenderObject() as RenderBox?;
    if (stackBox == null) {
      return;
    }
    final global = box.localToGlobal(box.size.center(Offset.zero));
    _powerButtonCenter = stackBox.globalToLocal(global);
  }

  void _onConnectLightSettled() {
    if (!mounted) {
      return;
    }
    setState(() {
      _connectLightActive = false;
      _connectLightHomeIn = false;
      _connectLightAbort = false;
      _checkingAccess = false;
    });
    _setConnected(true);
  }

  void _onConnectLightAborted() {
    if (!mounted) {
      return;
    }
    final message = _pendingAbortMessage;
    _pendingAbortMessage = null;
    setState(() {
      _connectLightActive = false;
      _connectLightHomeIn = false;
      _connectLightAbort = false;
      _checkingAccess = false;
    });
    if (message != null && message.isNotEmpty) {
      _showHomeMessage(message);
    }
  }

  void _showHomeMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF1A1A1A),
        content: Text(
          message,
          style: const TextStyle(color: Colors.white),
        ),
      ),
    );
  }

  Future<ActivationSuccess?> _showAccessKeyDialog() {
    return showDialog<ActivationSuccess>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return _AccessKeyDialog(
          activationApi: widget.activationApi,
          vpnConfigApi: widget.vpnConfigApi,
          secureVault: widget.secureVault,
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
        _startTunnelHealthPolling();
      } else {
        _stopTunnelHealthPolling();
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
    // Hide the glyph while the spark blooms — white-on-white reads as noise.
    final iconOpacity = _connectLightActive ? 0.0 : 1.0;

    final isDesktopShell = widget.desktopShell != null;

    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: Stack(
          key: _homeStackKey,
          children: [
            // Frameless Windows: drag strip under chrome buttons.
            if (isDesktopShell)
              const Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: 52,
                child: DragToMoveArea(child: SizedBox.expand()),
              ),
            Positioned(
              top: 4,
              left: 4,
              child: IconButton(
                tooltip: '',
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
            if (isDesktopShell)
              Positioned(
                top: 4,
                right: 4,
                child: IconButton(
                  tooltip: '',
                  onPressed: () {
                    unawaited(widget.desktopShell!.hideToTray());
                  },
                  icon: const Icon(
                    Icons.close,
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
                        key: _powerButtonKey,
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
                        child: AnimatedOpacity(
                          opacity: iconOpacity,
                          duration: Duration(
                            milliseconds: _connectLightActive ? 140 : 260,
                          ),
                          curve: _connectLightActive
                              ? Curves.easeIn
                              : Curves.easeOutCubic,
                          child: Icon(
                            Icons.power_settings_new,
                            size: 56,
                            color: iconColor,
                          ),
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
            if (_connectLightActive)
              Positioned.fill(
                child: ConnectingLightOverlay(
                  homeIn: _connectLightHomeIn,
                  abort: _connectLightAbort,
                  target: _powerButtonCenter == Offset.zero
                      ? Offset(
                          MediaQuery.sizeOf(context).width / 2,
                          MediaQuery.sizeOf(context).height / 2,
                        )
                      : _powerButtonCenter,
                  onSettled: _onConnectLightSettled,
                  onAborted: _onConnectLightAborted,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
class _AccessKeyDialog extends StatefulWidget {
  const _AccessKeyDialog({
    required this.activationApi,
    required this.vpnConfigApi,
    required this.secureVault,
  });

  final ActivationApi activationApi;
  final VpnConfigApi vpnConfigApi;
  final SecureVault secureVault;

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
      final deviceId = await widget.secureVault.getOrCreateDeviceId();
      final keyPair = await widget.secureVault.getOrCreateVpnKeyPair();
      final result = await widget.activationApi.activate(
        accessKey: accessKey,
        deviceId: deviceId,
        vpnPublicKey: keyPair.publicKeyBase64,
      );
      await widget.secureVault.saveAccessKey(accessKey);
      await widget.secureVault.saveActivationSuccess(vpnIp: result.vpnIp);

      final config = await widget.vpnConfigApi.fetchConfig(
        accessKey: accessKey,
        deviceId: deviceId,
      );
      await widget.secureVault.saveVpnConfig(config);

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
    } on VpnConfigException catch (error) {
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
                hintText: 'BRATAN-XXXXXXXXXXXXXXXX',
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
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
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
