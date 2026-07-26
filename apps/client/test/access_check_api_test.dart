import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:client/services/access_check_api.dart';

void main() {
  test('check maps valid status', () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/api/v1/validate');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['key'], 'BRATAN-TEST');
      expect(body['device_id'], 'device-1');
      return http.Response(
        jsonEncode({'status': 'valid'}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final api = AccessCheckApi(client: client);
    final status = await api.check(
      accessKey: 'BRATAN-TEST',
      deviceId: 'device-1',
    );
    expect(status, AccessCheckStatus.valid);
  });

  test('check maps revoked status', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({'status': 'revoked'}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final api = AccessCheckApi(client: client);
    final status = await api.check(accessKey: 'X', deviceId: 'Y');
    expect(status, AccessCheckStatus.revoked);
  });
}
