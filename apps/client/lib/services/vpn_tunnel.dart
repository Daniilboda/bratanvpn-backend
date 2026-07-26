/// Starts and stops the native VPN tunnel.
abstract class VpnTunnel {
  Future<void> start({required String confText});

  Future<void> stop();

  Future<bool> isRunning();
}

class VpnTunnelException implements Exception {
  VpnTunnelException(this.userMessage);

  final String userMessage;

  @override
  String toString() => userMessage;
}
