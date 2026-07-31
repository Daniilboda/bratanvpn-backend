import 'package:client/services/amnezia_config_builder.dart';
import 'package:client/services/diag_log.dart';
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
    final shortId = DiagLog.shortDeviceId(deviceId);

    await DiagLog.instance.info('connect_begin', {'device_id': shortId});

    if (accessKey == null || accessKey.isEmpty) {
      await DiagLog.instance.error('connect_fail', {
        'reason': 'no_access_key',
        'device_id': shortId,
      });
      throw VpnTunnelException('Ключ доступа не найден. Активируйте ключ заново.');
    }
    if (keyPair == null) {
      await DiagLog.instance.error('connect_fail', {
        'reason': 'no_vpn_keypair',
        'device_id': shortId,
      });
      throw VpnTunnelException('VPN-ключи не найдены. Активируйте ключ заново.');
    }

    late final String vpnIp;
    try {
      vpnIp = await sessionApi.connect(
        accessKey: accessKey,
        deviceId: deviceId,
      );
    } on VpnSessionException catch (error) {
      await DiagLog.instance.error('connect_api_fail', {
        'device_id': shortId,
        'http': error.statusCode,
        'msg': error.userMessage,
      });
      rethrow;
    }
    await vault.saveVpnIp(vpnIp);
    await DiagLog.instance.info('connect_api_ok', {
      'device_id': shortId,
      'vpn_ip': vpnIp,
    });

    late final Map<String, dynamic> vpnConfig;
    try {
      vpnConfig = await configApi.fetchConfig(
        accessKey: accessKey,
        deviceId: deviceId,
      );
      await vault.saveVpnConfig(vpnConfig);
      await DiagLog.instance.info('config_ok', {
        'device_id': shortId,
        'vpn_ip': vpnIp,
      });
    } on Object catch (error) {
      await DiagLog.instance.error('config_fail', {
        'device_id': shortId,
        'error': error.runtimeType,
      });
      rethrow;
    }

    final conf = configBuilder.build(
      privateKeyBase64: keyPair.privateKeyBase64,
      vpnConfig: vpnConfig,
    );

    try {
      await tunnel.start(confText: conf);
      await DiagLog.instance.info('tunnel_start_ok', {
        'device_id': shortId,
        'vpn_ip': vpnIp,
      });
    } on Object catch (error) {
      await DiagLog.instance.error('tunnel_start_fail', {
        'device_id': shortId,
        'vpn_ip': vpnIp,
        'error': error is VpnTunnelException
            ? error.userMessage
            : error.runtimeType,
      });
      // Best-effort: free server slot if local tunnel failed to start.
      try {
        await sessionApi.disconnect(
          accessKey: accessKey,
          deviceId: deviceId,
        );
        await vault.clearVpnIp();
        await DiagLog.instance.warn('connect_rollback_disconnect_ok', {
          'device_id': shortId,
        });
      } on Object {
        await DiagLog.instance.warn('connect_rollback_disconnect_fail', {
          'device_id': shortId,
        });
      }
      rethrow;
    }
  }

  Future<void> disconnect() async {
    final deviceId = await vault.readDeviceId();
    final shortId = DiagLog.shortDeviceId(deviceId);
    await DiagLog.instance.info('disconnect_begin', {'device_id': shortId});

    try {
      await tunnel.stop();
      await DiagLog.instance.info('tunnel_stop_ok', {'device_id': shortId});
    } on Object catch (error) {
      await DiagLog.instance.warn('tunnel_stop_fail', {
        'device_id': shortId,
        'error': error is VpnTunnelException
            ? error.userMessage
            : error.runtimeType,
      });
      rethrow;
    } finally {
      final accessKey = await vault.readAccessKey();
      if (accessKey != null &&
          accessKey.isNotEmpty &&
          deviceId != null &&
          deviceId.isNotEmpty) {
        try {
          await sessionApi.disconnect(
            accessKey: accessKey,
            deviceId: deviceId,
          );
          await DiagLog.instance.info('disconnect_api_ok', {
            'device_id': shortId,
          });
        } on Object catch (error) {
          await DiagLog.instance.warn('disconnect_api_fail', {
            'device_id': shortId,
            'error': error is VpnSessionException
                ? error.userMessage
                : error.runtimeType,
          });
        }
      }
      await vault.clearVpnIp();
      await vault.clearVpnConfig();
      await DiagLog.instance.info('disconnect_done', {'device_id': shortId});
    }
  }

  Future<bool> isRunning() => tunnel.isRunning();
}
