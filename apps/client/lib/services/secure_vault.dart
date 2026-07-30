import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import 'package:client/services/vpn_keypair.dart';

/// Keys stored in platform secure storage (Keystore / Credential Manager).
abstract final class SecureVaultKeys {
  static const deviceId = 'device_id';
  static const accessKey = 'access_key';
  static const vpnPrivateKey = 'vpn_private_key';
  static const vpnPublicKey = 'vpn_public_key';
  static const vpnIp = 'vpn_ip';
  static const vpnConfig = 'vpn_config';
  static const activated = 'activated';
}

/// Protected local store for device secrets and activation state.
class SecureVault {
  SecureVault({FlutterSecureStorage? storage, Uuid? uuid})
    : _storage = storage ?? const FlutterSecureStorage(),
      _uuid = uuid ?? const Uuid();

  final FlutterSecureStorage _storage;
  final Uuid _uuid;

  Future<String> getOrCreateDeviceId() async {
    final existing = await _storage.read(key: SecureVaultKeys.deviceId);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final created = _uuid.v4();
    await _storage.write(key: SecureVaultKeys.deviceId, value: created);
    return created;
  }

  Future<String?> readDeviceId() async {
    return _storage.read(key: SecureVaultKeys.deviceId);
  }

  Future<void> saveAccessKey(String accessKey) async {
    await _storage.write(key: SecureVaultKeys.accessKey, value: accessKey);
  }

  Future<String?> readAccessKey() async {
    return _storage.read(key: SecureVaultKeys.accessKey);
  }

  Future<VpnKeyPair?> readVpnKeyPair() async {
    final privateKey = await _storage.read(key: SecureVaultKeys.vpnPrivateKey);
    final publicKey = await _storage.read(key: SecureVaultKeys.vpnPublicKey);
    if (privateKey == null ||
        privateKey.isEmpty ||
        publicKey == null ||
        publicKey.isEmpty) {
      return null;
    }
    return VpnKeyPair(
      privateKeyBase64: privateKey,
      publicKeyBase64: publicKey,
    );
  }

  Future<VpnKeyPair> getOrCreateVpnKeyPair({
    Future<VpnKeyPair> Function() generator = generateVpnKeyPair,
  }) async {
    final existing = await readVpnKeyPair();
    if (existing != null) {
      return existing;
    }
    final created = await generator();
    await _storage.write(
      key: SecureVaultKeys.vpnPrivateKey,
      value: created.privateKeyBase64,
    );
    await _storage.write(
      key: SecureVaultKeys.vpnPublicKey,
      value: created.publicKeyBase64,
    );
    return created;
  }

  Future<void> saveVpnConfig(Map<String, dynamic> config) async {
    await _storage.write(
      key: SecureVaultKeys.vpnConfig,
      value: jsonEncode(config),
    );
  }

  Future<Map<String, dynamic>?> readVpnConfig() async {
    final raw = await _storage.read(key: SecureVaultKeys.vpnConfig);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      return null;
    }
    return decoded;
  }

  Future<void> saveActivationSuccess() async {
    await _storage.write(key: SecureVaultKeys.activated, value: 'true');
  }

  Future<bool> isActivated() async {
    final value = await _storage.read(key: SecureVaultKeys.activated);
    return value == 'true';
  }

  Future<void> saveVpnIp(String vpnIp) async {
    await _storage.write(key: SecureVaultKeys.vpnIp, value: vpnIp);
  }

  Future<String?> readVpnIp() async {
    return _storage.read(key: SecureVaultKeys.vpnIp);
  }

  Future<void> clearVpnIp() async {
    await _storage.delete(key: SecureVaultKeys.vpnIp);
  }

  Future<void> clearVpnConfig() async {
    await _storage.delete(key: SecureVaultKeys.vpnConfig);
  }

  /// Clears activation session after revoke / access loss.
  /// Keeps device_id and VPN keypair for a future new access key.
  Future<void> clearAccessSession() async {
    await _storage.delete(key: SecureVaultKeys.accessKey);
    await _storage.delete(key: SecureVaultKeys.vpnIp);
    await _storage.delete(key: SecureVaultKeys.vpnConfig);
    await _storage.delete(key: SecureVaultKeys.activated);
  }
}
