import 'package:client/services/amnezia_config_builder.dart';
import 'package:client/services/secure_vault.dart';
import 'package:client/services/vpn_tunnel.dart';

/// Orchestrates vault → .conf → native tunnel start/stop.
class VpnSession {
  VpnSession({
    required this.vault,
    required this.tunnel,
    this.configBuilder = const AmneziaConfigBuilder(),
  });

  final SecureVault vault;
  final VpnTunnel tunnel;
  final AmneziaConfigBuilder configBuilder;

  Future<void> connect() async {
    final keyPair = await vault.readVpnKeyPair();
    final vpnConfig = await vault.readVpnConfig();

    if (keyPair == null) {
      throw VpnTunnelException('VPN-ключи не найдены. Активируйте ключ заново.');
    }
    if (vpnConfig == null) {
      throw VpnTunnelException(
        'VPN-конфигурация не найдена. Активируйте ключ заново.',
      );
    }

    final conf = configBuilder.build(
      privateKeyBase64: keyPair.privateKeyBase64,
      vpnConfig: vpnConfig,
    );

    await tunnel.start(confText: conf);
  }

  Future<void> disconnect() async {
    await tunnel.stop();
  }

  Future<bool> isRunning() => tunnel.isRunning();
}
