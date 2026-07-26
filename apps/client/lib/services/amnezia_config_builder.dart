/// Builds an AmneziaWG/WireGuard-style `.conf` text from local secrets + API config.
///
/// Never log the returned string — it contains the private key.
class AmneziaConfigBuilder {
  const AmneziaConfigBuilder();

  /// [privateKeyBase64] — device private key (from vault).
  /// [vpnConfig] — JSON map from `GET /api/v1/vpn/config` (from vault).
  String build({
    required String privateKeyBase64,
    required Map<String, dynamic> vpnConfig,
    String dns = '1.1.1.1',
    String allowedIps = '0.0.0.0/0, ::/0',
    int persistentKeepalive = 25,
  }) {
    final privateKey = privateKeyBase64.trim();
    if (privateKey.isEmpty) {
      throw const AmneziaConfigException('Приватный VPN-ключ не найден.');
    }

    final server = vpnConfig['server'];
    final protocol = vpnConfig['protocol'];
    final client = vpnConfig['client'];

    if (server is! Map<String, dynamic> ||
        protocol is! Map<String, dynamic> ||
        client is! Map<String, dynamic>) {
      throw const AmneziaConfigException('VPN-конфигурация повреждена.');
    }

    final host = server['host'] as String?;
    final port = server['port'];
    final serverPublicKey = server['public_key'] as String?;
    final vpnIpRaw = client['vpn_ip'] as String?;

    if (host == null ||
        host.isEmpty ||
        serverPublicKey == null ||
        serverPublicKey.isEmpty ||
        vpnIpRaw == null ||
        vpnIpRaw.isEmpty ||
        port is! int) {
      throw const AmneziaConfigException('VPN-конфигурация неполная.');
    }

    final address = vpnIpRaw.contains('/') ? vpnIpRaw : '$vpnIpRaw/32';
    final endpoint = '$host:$port';

    final protocolConfig = protocol['config'];
    final awg = protocolConfig is Map<String, dynamic> ? protocolConfig : null;

    final buffer = StringBuffer()
      ..writeln('[Interface]')
      ..writeln('PrivateKey = $privateKey')
      ..writeln('Address = $address')
      ..writeln('DNS = $dns');

    if (awg != null) {
      _writeOptionalInt(buffer, 'Jc', awg['jc']);
      _writeOptionalInt(buffer, 'Jmin', awg['jmin']);
      _writeOptionalInt(buffer, 'Jmax', awg['jmax']);
      _writeOptionalInt(buffer, 'S1', awg['s1']);
      _writeOptionalInt(buffer, 'S2', awg['s2']);
      _writeOptionalInt(buffer, 'S3', awg['s3']);
      _writeOptionalInt(buffer, 'S4', awg['s4']);
      _writeOptionalInt(buffer, 'H1', awg['h1']);
      _writeOptionalInt(buffer, 'H2', awg['h2']);
      _writeOptionalInt(buffer, 'H3', awg['h3']);
      _writeOptionalInt(buffer, 'H4', awg['h4']);
      final i1 = awg['i1'];
      if (i1 is String && i1.trim().isNotEmpty) {
        buffer.writeln('I1 = ${i1.trim()}');
      }
    }

    buffer
      ..writeln()
      ..writeln('[Peer]')
      ..writeln('PublicKey = $serverPublicKey')
      ..writeln('Endpoint = $endpoint')
      ..writeln('AllowedIPs = $allowedIps')
      ..writeln('PersistentKeepalive = $persistentKeepalive');

    return buffer.toString();
  }

  void _writeOptionalInt(StringBuffer buffer, String key, Object? value) {
    if (value is int) {
      buffer.writeln('$key = $value');
    } else if (value is String && value.trim().isNotEmpty) {
      buffer.writeln('$key = ${value.trim()}');
    }
  }
}

class AmneziaConfigException implements Exception {
  const AmneziaConfigException(this.userMessage);

  final String userMessage;

  @override
  String toString() => userMessage;
}
