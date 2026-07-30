import 'package:client/services/amnezia_config_builder.dart';
import 'package:client/services/secure_vault.dart';
import 'package:client/services/vpn_config_api.dart';
import 'package:client/services/vpn_session_api.dart';
import 'package:client/services/vpn_tunnel.dart';

/// Orchestrates session API → vault → .conf → native tunnel start/stop.
class VpnSession {
  VpnSession({
    required this.vault,
    required this.tunnel,
    VpnSessionApi? sessionApi,
    VpnConfigApi? configApi,
    this.configBuilder = const AmneziaConfigBuilder(),
  }) : sessionApi = sessionApi ?? VpnSessionApi(),
       configApi = configApi ?? VpnConfigApi();

  final SecureVault vault;
  final VpnTunnel tunnel;
  final VpnSessionApi sessionApi;
  final VpnConfigApi configApi;
  final AmneziaConfigBuilder configBuilder;

  Future<void> connect() async {
    final accessKey = await vault.readAccessKey();
    final deviceId = await vault.getOrCreateDeviceId();
    final keyPair = await vault.readVpnKeyPair();

    if (accessKey == null || accessKey.isEmpty) {
      throw VpnTunnelException('Ключ доступа не найден. Активируйте ключ заново.');
    }
    if (keyPair == null) {
      throw VpnTunnelException('VPN-ключи не найдены. Активируйте ключ заново.');
    }

    final vpnIp = await sessionApi.connect(
      accessKey: accessKey,
      deviceId: deviceId,
    );
    await vault.saveVpnIp(vpnIp);

    final vpnConfig = await configApi.fetchConfig(
      accessKey: accessKey,
      deviceId: deviceId,
    );
    await vault.saveVpnConfig(vpnConfig);

    final conf = configBuilder.build(
      privateKeyBase64: keyPair.privateKeyBase64,
      vpnConfig: vpnConfig,
    );

    try {
      await tunnel.start(confText: conf);
    } on Object {
      // Best-effort: free server slot if local tunnel failed to start.
      try {
        await sessionApi.disconnect(
          accessKey: accessKey,
          deviceId: deviceId,
        );
        await vault.clearVpnIp();
      } on Object {
        // Ignore secondary failures.
      }
      rethrow;
    }
  }

  Future<void> disconnect() async {
    try {
      await tunnel.stop();
    } finally {
      final accessKey = await vault.readAccessKey();
      final deviceId = await vault.readDeviceId();
      if (accessKey != null &&
          accessKey.isNotEmpty &&
          deviceId != null &&
          deviceId.isNotEmpty) {
        try {
          await sessionApi.disconnect(
            accessKey: accessKey,
            deviceId: deviceId,
          );
        } on Object {
          // Local stop already done; server cleanup can retry next connect.
        }
      }
      await vault.clearVpnIp();
      await vault.clearVpnConfig();
    }
  }

  Future<bool> isRunning() => tunnel.isRunning();
}
