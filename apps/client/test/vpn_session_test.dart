import 'package:flutter_test/flutter_test.dart';

import 'package:client/services/secure_vault.dart';
import 'package:client/services/vpn_keypair.dart';
import 'package:client/services/vpn_session.dart';
import 'package:client/services/vpn_tunnel.dart';
import 'package:client/services/vpn_tunnel_stub.dart';

class _MemoryVault extends SecureVault {
  final Map<String, String> store = {};

  @override
  Future<VpnKeyPair?> readVpnKeyPair() async {
    return const VpnKeyPair(
      privateKeyBase64: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
      publicKeyBase64: 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=',
    );
  }

  @override
  Future<Map<String, dynamic>?> readVpnConfig() async {
    return {
      'server': {
        'host': '1.2.3.4',
        'port': 51820,
        'public_key': 'SERVERPUBLICKEYAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
      },
      'protocol': {
        'type': 'amneziawg',
        'config': {'jc': 4, 'jmin': 64, 'jmax': 1024},
      },
      'client': {'vpn_ip': '10.8.0.5'},
    };
  }
}

void main() {
  test('VpnSession connect starts stub tunnel', () async {
    final tunnel = StubVpnTunnel();
    final session = VpnSession(vault: _MemoryVault(), tunnel: tunnel);

    await session.connect();
    expect(await tunnel.isRunning(), isTrue);

    await session.disconnect();
    expect(await tunnel.isRunning(), isFalse);
  });

  test('VpnSession fails without keypair', () async {
    final emptyVault = _EmptyVault();
    final session = VpnSession(vault: emptyVault, tunnel: StubVpnTunnel());

    await expectLater(
      session.connect(),
      throwsA(
        isA<VpnTunnelException>().having(
          (e) => e.userMessage,
          'msg',
          contains('ключ'),
        ),
      ),
    );
  });
}

class _EmptyVault extends SecureVault {
  @override
  Future<VpnKeyPair?> readVpnKeyPair() async => null;

  @override
  Future<Map<String, dynamic>?> readVpnConfig() async => null;
}
