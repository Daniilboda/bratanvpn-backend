import 'dart:convert';

import 'package:cryptography/cryptography.dart';

/// WireGuard/AmneziaWG-compatible X25519 key pair (base64 with padding).
class VpnKeyPair {
  const VpnKeyPair({
    required this.privateKeyBase64,
    required this.publicKeyBase64,
  });

  final String privateKeyBase64;
  final String publicKeyBase64;
}

/// Generates a new Curve25519 key pair for the VPN tunnel.
///
/// Private key must never leave the device / never go to the backend.
Future<VpnKeyPair> generateVpnKeyPair() async {
  final algorithm = X25519();
  final keyPair = await algorithm.newKeyPair();
  final privateBytes = await keyPair.extractPrivateKeyBytes();
  final publicKey = await keyPair.extractPublicKey();

  return VpnKeyPair(
    privateKeyBase64: base64Encode(privateBytes),
    publicKeyBase64: base64Encode(publicKey.bytes),
  );
}
