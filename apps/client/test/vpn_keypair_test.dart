import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:client/services/vpn_keypair.dart';

void main() {
  test('generateVpnKeyPair returns WireGuard-shaped base64 keys', () async {
    final pair = await generateVpnKeyPair();

    final publicKeyRe = RegExp(r'^[A-Za-z0-9+/]{43}=$');
    expect(publicKeyRe.hasMatch(pair.publicKeyBase64), isTrue);
    expect(publicKeyRe.hasMatch(pair.privateKeyBase64), isTrue);

    expect(base64Decode(pair.publicKeyBase64), hasLength(32));
    expect(base64Decode(pair.privateKeyBase64), hasLength(32));
    expect(pair.publicKeyBase64, isNot(equals(pair.privateKeyBase64)));
  });
}
