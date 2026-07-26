import 'package:flutter_test/flutter_test.dart';

import 'package:client/services/amnezia_config_builder.dart';

void main() {
  const builder = AmneziaConfigBuilder();

  final sampleConfig = <String, dynamic>{
    'schema_version': 1,
    'server': {
      'name': 'Основной',
      'host': '89.125.16.255',
      'port': 51820,
      'public_key': 'SERVERPUBLICKEYAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
    },
    'protocol': {
      'type': 'amneziawg',
      'config': {
        'jc': 4,
        'jmin': 64,
        'jmax': 1024,
        's1': 32,
        's2': 48,
        's3': 24,
        's4': 12,
        'h1': 1234567891,
        'h2': 1234567892,
        'h3': 1234567893,
        'h4': 1234567894,
        'i1': '',
      },
    },
    'client': {'vpn_ip': '10.8.0.2'},
  };

  test('builds Interface and Peer with Amnezia params', () {
    final conf = builder.build(
      privateKeyBase64: 'CLIENTPRIVATEKEYAAAAAAAAAAAAAAAAAAAAAAAAA=',
      vpnConfig: sampleConfig,
    );

    expect(conf, contains('[Interface]'));
    expect(conf, contains('PrivateKey = CLIENTPRIVATEKEYAAAAAAAAAAAAAAAAAAAAAAAAA='));
    expect(conf, contains('Address = 10.8.0.2/32'));
    expect(conf, contains('DNS = 1.1.1.1'));
    expect(conf, contains('Jc = 4'));
    expect(conf, contains('Jmin = 64'));
    expect(conf, contains('H1 = 1234567891'));
    expect(conf, isNot(contains('I1 =')));
    expect(conf, contains('[Peer]'));
    expect(conf, contains('PublicKey = SERVERPUBLICKEYAAAAAAAAAAAAAAAAAAAAAAAAAAA='));
    expect(conf, contains('Endpoint = 89.125.16.255:51820'));
    expect(conf, contains('AllowedIPs = 0.0.0.0/0, ::/0'));
    expect(conf, contains('PersistentKeepalive = 25'));
  });

  test('includes I1 when non-empty', () {
    final config = Map<String, dynamic>.from(sampleConfig);
    config['protocol'] = {
      'type': 'amneziawg',
      'config': {
        ...(sampleConfig['protocol'] as Map<String, dynamic>)['config']
            as Map<String, dynamic>,
        'i1': '<r 1>',
      },
    };

    final conf = builder.build(
      privateKeyBase64: 'CLIENTPRIVATEKEYAAAAAAAAAAAAAAAAAAAAAAAAA=',
      vpnConfig: config,
    );

    expect(conf, contains('I1 = <r 1>'));
  });

  test('throws on missing private key', () {
    expect(
      () => builder.build(privateKeyBase64: '  ', vpnConfig: sampleConfig),
      throwsA(isA<AmneziaConfigException>()),
    );
  });
}
