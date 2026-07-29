import 'package:flutter/services.dart';

import 'package:client/services/vpn_tunnel.dart';

/// Android tunnel via Kotlin [VpnService] + MethodChannel.
class AndroidVpnTunnel implements VpnTunnel {
  static const MethodChannel _channel = MethodChannel('com.bratanvpn.client/vpn');

  @override
  Future<void> start({required String confText}) async {
    if (confText.trim().isEmpty) {
      throw VpnTunnelException('Пустая VPN-конфигурация.');
    }

    try {
      // Clear orphan tunnel left after revoke / failed UI handoff.
      if (await isRunning()) {
        await stop();
      }
      final prepared = await _channel.invokeMethod<bool>('prepare');
      if (prepared != true) {
        throw VpnTunnelException('Разрешение VPN не выдано.');
      }
      await _channel.invokeMethod<void>('start', <String, dynamic>{
        'confText': confText,
      });
    } on PlatformException catch (e) {
      throw VpnTunnelException(_mapError(e));
    } on MissingPluginException {
      throw VpnTunnelException('VPN-модуль Android недоступен.');
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } on PlatformException catch (e) {
      throw VpnTunnelException(_mapError(e));
    } on MissingPluginException {
      // ignore on tear-down
    }
  }

  @override
  Future<bool> isRunning() async {
    try {
      final running = await _channel.invokeMethod<bool>('isRunning');
      return running ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  String _mapError(PlatformException e) {
    switch (e.code) {
      case 'VPN_PERMISSION_REQUIRED':
        return 'Нужно разрешение VPN. Разрешите доступ и повторите.';
      case 'VPN_START_FAILED':
        return e.message?.trim().isNotEmpty == true
            ? e.message!.trim()
            : 'Не удалось запустить VPN.';
      case 'INVALID_CONF':
        return 'Пустая VPN-конфигурация.';
      default:
        final msg = e.message?.trim();
        if (msg != null && msg.isNotEmpty) return msg;
        return 'Ошибка VPN на Android.';
    }
  }
}
