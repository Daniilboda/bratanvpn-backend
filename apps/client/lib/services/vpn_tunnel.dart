/// Starts and stops the native VPN tunnel.
abstract class VpnTunnel {
  Future<void> start({required String confText});

  Future<void> stop();

  Future<bool> isRunning();
}

class VpnTunnelException implements Exception {
  VpnTunnelException(this.userMessage, {this.detail});

  /// Safe message for UI.
  final String userMessage;

  /// Technical detail for diag logs (e.g. raw helper pipe response). Not for UI.
  final String? detail;

  @override
  String toString() => userMessage;
}
