import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'package:client/platform/desktop_shell.dart';
import 'package:client/services/access_check_api.dart';
import 'package:client/services/activation_api.dart';
import 'package:client/services/amnezia_config_builder.dart';
import 'package:client/services/api_config.dart';
import 'package:client/services/diag_log.dart';
import 'package:client/services/secure_vault.dart';
import 'package:client/services/vpn_config_api.dart';
import 'package:client/services/vpn_session.dart';
import 'package:client/services/vpn_session_api.dart';
import 'package:client/services/vpn_tunnel.dart';
import 'package:client/services/vpn_tunnel_factory.dart';
import 'package:client/shared/widgets/connecting_light_overlay.dart';
import 'package:client/shared/widgets/drakar_medallion_button.dart';
import 'package:client/shared/widgets/drakar_server_card.dart';

/// Matches [assets/drakar/bg_texture.png] mean charcoal (window/scaffold fallback).
const Color kDrakarBackground = Color(0xFF060606);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // New file per app launch (= one manual check session). Older logs kept.
  await DiagLog.instance.startCheck(reason: 'app_start');
  await DiagLog.instance.info('api_base_url', {'url': apiBaseUrl});

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
    this.vpnSessionApi,
    this.accessCheckApi,
    this.secureVault,
    this.vpnTunnel,
    this.desktopShell,
  });

  final ActivationApi? activationApi;
  final VpnConfigApi? vpnConfigApi;
  final VpnSessionApi? vpnSessionApi;
  final AccessCheckApi? accessCheckApi;
  final SecureVault? secureVault;
  final VpnTunnel? vpnTunnel;
  final DesktopShell? desktopShell;

  @override
  Widget build(BuildContext context) {
    final vault = secureVault ?? SecureVault();
    final tunnel = vpnTunnel ?? createVpnTunnel();
    final configApi = vpnConfigApi ?? VpnConfigApi();

    return MaterialApp(
      title: 'BratanVPN',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: kDrakarBackground,
        colorScheme: const ColorScheme.dark(
          primary: Colors.white,
          onPrimary: kDrakarBackground,
          surface: kDrakarBackground,
          onSurface: Colors.white,
        ),
      ),
      home: HomePage(
        activationApi: activationApi ?? ActivationApi(),
        vpnConfigApi: configApi,
        accessCheckApi: accessCheckApi ?? AccessCheckApi(),
        secureVault: vault,
        vpnSession: VpnSession(
          vault: vault,
          tunnel: tunnel,
          sessionApi: vpnSessionApi ?? VpnSessionApi(),
          configApi: configApi,
        ),
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

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  static const Color _background = kDrakarBackground;
  static const String _bgTextureAsset = 'assets/drakar/bg_texture.png';
  // Цвет статуса «ПОДКЛЮЧЕНО» — правь здесь (реф ≈ #1CCB58).
  static const Color _statusConnected = Color(0xFF1CCB58);
  static const Color _statusDisconnected = Color(0xFFB0B0B0);
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
  /// Invalidates in-flight connect (revoke / new tap) so UI cannot get stuck.
  int _connectEpoch = 0;
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
    WidgetsBinding.instance.addObserver(this);
    widget.desktopShell?.beforeQuit = _onBeforeQuit;
    _restoreActivation();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Spec: validate while the app stays alive (incl. tray / background).
    // Resume catches revoke sooner than the 15-minute tick alone.
    if (state == AppLifecycleState.resumed && _keyActivated) {
      unawaited(_pollAccess());
    }
    // flutter run `q` — flush diag log. Do not use `hidden` (close-to-tray).
    if (state == AppLifecycleState.detached) {
      unawaited(DiagLog.instance.endCheck(reason: 'app_detached'));
    }
  }

  Future<void> _onBeforeQuit() async {
    try {
      await widget.vpnSession.disconnect();
    } on Object {
      // Best-effort stop on exit.
    }
    await DiagLog.instance.endCheck(reason: 'tray_quit');
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
    final logPath = DiagLog.instance.currentPath;

    if (!mounted) {
      return;
    }

    setState(() {
      _keyActivated = activated;
      _ready = true;
    });

    if (logPath != null) {
      await DiagLog.instance.info('ui_ready', {
        'activated': activated,
      });
      // Brief hint so the check-B log path is visible without hunting.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _showHomeMessage('Лог проверки: $logPath');
      });
    }

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
    await DiagLog.instance.warn('tunnel_dropped');
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

  Future<bool> _checkAccess({bool showBlockedAlert = true}) async {
    final accessKey = await widget.secureVault.readAccessKey();
    final deviceId = await widget.secureVault.getOrCreateDeviceId();
    final shortId = DiagLog.shortDeviceId(deviceId);

    if (accessKey == null || accessKey.isEmpty) {
      if (_keyActivated) {
        await DiagLog.instance.warn('validate_no_access_key', {
          'device_id': shortId,
        });
        await _applyAccessBlocked(
          message: 'Доступ заблокирован.',
          showAlert: showBlockedAlert,
        );
      }
      return false;
    }

    try {
      final status = await widget.accessCheckApi.check(
        accessKey: accessKey,
        deviceId: deviceId,
      );

      if (status == AccessCheckStatus.valid) {
        await DiagLog.instance.info('validate_ok', {'device_id': shortId});
        return true;
      }

      await DiagLog.instance.warn('validate_blocked', {
        'device_id': shortId,
        'status': status.name,
      });
      await _applyAccessBlocked(
        message: _messageForAccessStatus(status),
        showAlert: showBlockedAlert,
      );
      return false;
    } on AccessCheckException catch (error) {
      await DiagLog.instance.warn('validate_api_error', {
        'device_id': shortId,
        'msg': error.userMessage,
      });
      // Network / API errors: keep session; do not kick the user offline.
      return false;
    }
  }

  String _messageForAccessStatus(AccessCheckStatus status) {
    return switch (status) {
      AccessCheckStatus.revoked =>
        'Ключ отозван. Доступ заблокирован.',
      AccessCheckStatus.notFound => 'Ключ не найден.',
      AccessCheckStatus.deviceMismatch =>
        'Ключ уже активирован на другом устройстве.',
      AccessCheckStatus.readyToActivate =>
        'Ключ нужно активировать заново.',
      AccessCheckStatus.unknown || AccessCheckStatus.valid =>
        'Доступ заблокирован.',
    };
  }

  Future<void> _applyAccessBlocked({
    String message = 'Доступ заблокирован.',
    bool showAlert = true,
  }) async {
    await DiagLog.instance.warn('access_blocked', {'msg': message});
    // Cancel any in-flight connect / pulse so the power button unsticks.
    _connectEpoch++;
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
    _pendingAbortMessage = null;
    setState(() {
      _connectLightActive = false;
      _connectLightHomeIn = false;
      _connectLightAbort = false;
      _keyActivated = false;
      _connected = false;
      _checkingAccess = false;
      _session = Duration.zero;
    });
    if (showAlert) {
      await _showAccessAlert(message);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (widget.desktopShell?.beforeQuit == _onBeforeQuit) {
      widget.desktopShell?.beforeQuit = null;
    }
    _stopAccessPolling();
    _stopTunnelHealthPolling();
    _timer?.cancel();
    // Best-effort: flutter `q` often tears down via dispose.
    unawaited(DiagLog.instance.endCheck(reason: 'dispose'));
    super.dispose();
  }

  Future<void> _onPowerPressed() async {
    if (!_ready || _checkingAccess) {
      return;
    }

    if (_connected) {
      setState(() => _checkingAccess = true);
      await DiagLog.instance.info('ui_disconnect_tap');
      try {
        await widget.vpnSession.disconnect();
        if (!mounted) {
          return;
        }
        _setConnected(false);
      } on VpnTunnelException catch (error) {
        await DiagLog.instance.error('ui_disconnect_fail', {
          'msg': error.userMessage,
        });
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
    await DiagLog.instance.info('ui_connect_tap');
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
    final epoch = ++_connectEpoch;
    _updatePowerButtonCenter();
    // Immediate feedback: spark ignites at the button center.
    setState(() {
      _checkingAccess = true;
      _connectLightActive = true;
      _connectLightHomeIn = false;
      _connectLightAbort = false;
    });
    try {
      final pulseStartedAt = DateTime.now();
      await widget.vpnSession.connect();
      if (!mounted || epoch != _connectEpoch) {
        await _safeDisconnect();
        return;
      }
      // Android tunnel is often ready in <0.5s; keep the pulse as long as on Windows.
      if (!kIsWeb && Platform.isAndroid) {
        final elapsed = DateTime.now().difference(pulseStartedAt);
        final remaining =
            ConnectingLightOverlay.androidMinPulse - elapsed;
        if (remaining > Duration.zero) {
          await Future<void>.delayed(remaining);
          if (!mounted || epoch != _connectEpoch) {
            await _safeDisconnect();
            return;
          }
        }
      }
      _updatePowerButtonCenter();
      // Spark flares into the lit button.
      setState(() => _connectLightHomeIn = true);
    } on AmneziaConfigException catch (error) {
      await DiagLog.instance.error('ui_connect_fail', {
        'kind': 'config_build',
        'msg': error.userMessage,
      });
      if (mounted && epoch == _connectEpoch) {
        _abortConnectLight(error.userMessage);
      }
    } on VpnSessionException catch (error) {
      await DiagLog.instance.error('ui_connect_fail', {
        'kind': 'session',
        'http': error.statusCode,
        'msg': error.userMessage,
      });
      if (mounted && epoch == _connectEpoch) {
        _abortConnectLight(error.userMessage);
      }
    } on VpnConfigException catch (error) {
      await DiagLog.instance.error('ui_connect_fail', {
        'kind': 'config_api',
        'msg': error.userMessage,
      });
      if (mounted && epoch == _connectEpoch) {
        _abortConnectLight(error.userMessage);
      }
    } on VpnTunnelException catch (error) {
      await DiagLog.instance.error('ui_connect_fail', {
        'kind': 'tunnel',
        'msg': error.userMessage,
      });
      if (mounted && epoch == _connectEpoch) {
        _abortConnectLight(error.userMessage);
      }
    } on Exception catch (error) {
      await DiagLog.instance.error('ui_connect_fail', {
        'kind': 'unknown',
        'error': error.runtimeType,
      });
      if (mounted && epoch == _connectEpoch) {
        _abortConnectLight('Не удалось запустить VPN.');
      }
    }
  }

  Future<void> _safeDisconnect() async {
    try {
      await widget.vpnSession.disconnect();
    } on Object {
      // ignore
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _connectLightActive = false;
      _connectLightHomeIn = false;
      _connectLightAbort = false;
      _checkingAccess = false;
      _connected = false;
    });
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
      unawaited(_showAccessAlert(message));
    }
  }

  Future<void> _showAccessAlert(String message) async {
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.35)),
          ),
          title: const Text(
            'BratanVPN',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          content: Text(
            message,
            style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.35),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text(
                'Понятно',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Transient non-blocking hint (kept for rare cases).
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
    final label = _connected ? 'ПОДКЛЮЧЕНО' : 'ОТКЛЮЧЕНО';
    final labelColor =
        _connected ? _statusConnected : _statusDisconnected;

    final isDesktopShell = widget.desktopShell != null;

    return Scaffold(
      backgroundColor: _background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: Image.asset(
              _bgTextureAsset,
              fit: BoxFit.cover,
              alignment: Alignment.center,
              filterQuality: FilterQuality.medium,
            ),
          ),
          SafeArea(
            child: Stack(
              key: _homeStackKey,
              children: [
            // Frameless Windows: drag strip under chrome buttons.
            if (isDesktopShell)
              const Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: 64,
                child: DragToMoveArea(child: SizedBox.expand()),
              ),
            Positioned(
              top: 16,
              left: 8,
              child: IconButton(
                tooltip: '',
                onPressed: () {
                  // Экран настроек / меню добавим позже.
                },
                icon: Image.asset(
                  'assets/drakar/menu.png',
                  width: 26,
                  height: 22,
                  filterQuality: FilterQuality.high,
                ),
              ),
            ),
            if (isDesktopShell)
              Positioned(
                top: 16,
                right: 8,
                child: IconButton(
                  tooltip: '',
                  onPressed: () {
                    unawaited(widget.desktopShell!.hideToTray());
                  },
                  icon: Image.asset(
                    'assets/drakar/close.png',
                    width: 22,
                    height: 22,
                    filterQuality: FilterQuality.high,
                  ),
                ),
              ),
            // Hero stack: larger medallion, status tucked under (wordmark off for now).
            Align(
              alignment: const Alignment(0, -0.06),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DrakarMedallionButton(
                    buttonKey: _powerButtonKey,
                    connected: _connected,
                    onTap: _onPowerPressed,
                    diameter: 200,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: labelColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.8,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _sessionLabel,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.72),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 28,
              child: DrakarServerCard(connected: _connected),
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
        ],
      ),
    );
  }
}
class _AccessKeyDialog extends StatefulWidget {
  const _AccessKeyDialog({
    required this.activationApi,
    required this.secureVault,
  });

  final ActivationApi activationApi;
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
      final shortId = DiagLog.shortDeviceId(deviceId);
      await DiagLog.instance.info('bind_begin', {'device_id': shortId});
      final result = await widget.activationApi.activate(
        accessKey: accessKey,
        deviceId: deviceId,
        vpnPublicKey: keyPair.publicKeyBase64,
      );
      await widget.secureVault.saveAccessKey(accessKey);
      await widget.secureVault.saveActivationSuccess();
      await DiagLog.instance.info('bind_ok', {
        'device_id': shortId,
      });

      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(result);
    } on ActivationException catch (error) {
      await DiagLog.instance.error('bind_fail', {'msg': error.userMessage});
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = error.userMessage;
      });
    } on Exception catch (error) {
      await DiagLog.instance.error('bind_fail', {
        'error': error.runtimeType,
        'msg': error.toString(),
      });
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = error is ActivationException
            ? error.userMessage
            : 'Нет связи с API. Подробности в логе.';
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
                style: const TextStyle(
                  color: Color(0xFFFF5252),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
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
