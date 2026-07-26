import 'package:client/services/vpn_tunnel.dart';

/// Placeholder for platforms without a native tunnel yet (e.g. tests, Android WIP).
class StubVpnTunnel implements VpnTunnel {
  bool _running = false;

  /// Test helper: pretend the OS tunnel died while the app still thinks it is up.
  void simulateDrop() {
    _running = false;
  }

  @override
  Future<void> start({required String confText}) async {
    if (confText.trim().isEmpty) {
      throw VpnTunnelException('Пустая VPN-конфигурация.');
    }
    _running = true;
  }

  @override
  Future<void> stop() async {
    _running = false;
  }

  @override
  Future<bool> isRunning() async => _running;
}
