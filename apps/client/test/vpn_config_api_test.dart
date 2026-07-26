import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:client/services/vpn_config_api.dart';

void main() {
  test('fetchConfig returns JSON map on 200', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/api/v1/vpn/config');
      expect(request.url.queryParameters['access_key'], 'BRATAN-TEST');
      expect(request.url.queryParameters['device_id'], 'device-1');
      return http.Response(
        jsonEncode({
          'schema_version': 1,
          'client': {'vpn_ip': '10.8.0.2'},
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final api = VpnConfigApi(client: client);
    final config = await api.fetchConfig(
      accessKey: 'BRATAN-TEST',
      deviceId: 'device-1',
    );

    expect(config['schema_version'], 1);
    expect(config['client'], {'vpn_ip': '10.8.0.2'});
  });

  test('fetchConfig maps revoked to user message', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({'detail': 'Access key is revoked'}),
        403,
        headers: {'content-type': 'application/json'},
      );
    });

    final api = VpnConfigApi(client: client);
    expect(
      () => api.fetchConfig(accessKey: 'X', deviceId: 'Y'),
      throwsA(
        isA<VpnConfigException>().having(
          (e) => e.userMessage,
          'userMessage',
          'Доступ заблокирован.',
        ),
      ),
    );
  });
}
