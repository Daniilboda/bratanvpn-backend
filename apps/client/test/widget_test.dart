import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:client/main.dart';
import 'package:client/services/access_check_api.dart';
import 'package:client/services/activation_api.dart';
import 'package:client/services/secure_vault.dart';
import 'package:client/services/vpn_config_api.dart';
import 'package:client/services/vpn_keypair.dart';
import 'package:client/services/vpn_tunnel_stub.dart';

class _FakeActivationApi extends ActivationApi {
  _FakeActivationApi({this.failWith});

  final ActivationException? failWith;
  int calls = 0;
  String? lastDeviceId;
  String? lastPublicKey;

  @override
  Future<ActivationSuccess> activate({
    required String accessKey,
    required String deviceId,
    required String vpnPublicKey,
  }) async {
    calls += 1;
    lastDeviceId = deviceId;
    lastPublicKey = vpnPublicKey;
    if (failWith != null) {
      throw failWith!;
    }
    return const ActivationSuccess(vpnIp: '10.8.0.2');
  }
}

Map<String, dynamic> _sampleVpnConfig() => {
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
          'h1': 1,
          'h2': 2,
          'h3': 3,
          'h4': 4,
          'i1': '',
        },
      },
      'client': {'vpn_ip': '10.8.0.2'},
    };

class _FakeVpnConfigApi extends VpnConfigApi {
  _FakeVpnConfigApi({this.failWith});

  final VpnConfigException? failWith;
  int calls = 0;
  String? lastAccessKey;
  String? lastDeviceId;

  @override
  Future<Map<String, dynamic>> fetchConfig({
    required String accessKey,
    required String deviceId,
  }) async {
    calls += 1;
    lastAccessKey = accessKey;
    lastDeviceId = deviceId;
    if (failWith != null) {
      throw failWith!;
    }
    return _sampleVpnConfig();
  }
}

class _FakeAccessCheckApi extends AccessCheckApi {
  _FakeAccessCheckApi({this.status = AccessCheckStatus.valid});

  AccessCheckStatus status;
  int calls = 0;

  @override
  Future<AccessCheckStatus> check({
    required String accessKey,
    required String deviceId,
  }) async {
    calls += 1;
    return status;
  }
}

/// In-memory vault for widget tests (no platform secure storage).
class _FakeSecureVault extends SecureVault {
  final Map<String, String> store = {};

  @override
  Future<String> getOrCreateDeviceId() async {
    return store.putIfAbsent(SecureVaultKeys.deviceId, () => 'test-device-1');
  }

  @override
  Future<void> saveAccessKey(String accessKey) async {
    store[SecureVaultKeys.accessKey] = accessKey;
  }

  @override
  Future<String?> readAccessKey() async => store[SecureVaultKeys.accessKey];

  @override
  Future<VpnKeyPair?> readVpnKeyPair() async {
    final privateKey = store[SecureVaultKeys.vpnPrivateKey];
    final publicKey = store[SecureVaultKeys.vpnPublicKey];
    if (privateKey == null || publicKey == null) {
      return null;
    }
    return VpnKeyPair(
      privateKeyBase64: privateKey,
      publicKeyBase64: publicKey,
    );
  }

  @override
  Future<VpnKeyPair> getOrCreateVpnKeyPair({
    Future<VpnKeyPair> Function() generator = generateVpnKeyPair,
  }) async {
    final existing = await readVpnKeyPair();
    if (existing != null) {
      return existing;
    }
    const created = VpnKeyPair(
      privateKeyBase64: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
      publicKeyBase64: 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=',
    );
    store[SecureVaultKeys.vpnPrivateKey] = created.privateKeyBase64;
    store[SecureVaultKeys.vpnPublicKey] = created.publicKeyBase64;
    return created;
  }

  @override
  Future<void> saveVpnConfig(Map<String, dynamic> config) async {
    store[SecureVaultKeys.vpnConfig] = jsonEncode(config);
  }

  @override
  Future<Map<String, dynamic>?> readVpnConfig() async {
    final raw = store[SecureVaultKeys.vpnConfig];
    if (raw == null || raw.isEmpty) {
      return null;
    }
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  @override
  Future<void> saveActivationSuccess({required String vpnIp}) async {
    store[SecureVaultKeys.vpnIp] = vpnIp;
    store[SecureVaultKeys.activated] = 'true';
  }

  @override
  Future<bool> isActivated() async => store[SecureVaultKeys.activated] == 'true';

  @override
  Future<String?> readVpnIp() async => store[SecureVaultKeys.vpnIp];

  @override
  Future<void> clearAccessSession() async {
    store.remove(SecureVaultKeys.accessKey);
    store.remove(SecureVaultKeys.vpnIp);
    store.remove(SecureVaultKeys.vpnConfig);
    store.remove(SecureVaultKeys.activated);
  }
}

Widget _app({
  ActivationApi? activationApi,
  VpnConfigApi? vpnConfigApi,
  AccessCheckApi? accessCheckApi,
  SecureVault? secureVault,
  StubVpnTunnel? vpnTunnel,
}) {
  return MyApp(
    activationApi: activationApi ?? _FakeActivationApi(),
    vpnConfigApi: vpnConfigApi ?? _FakeVpnConfigApi(),
    accessCheckApi: accessCheckApi ?? _FakeAccessCheckApi(),
    secureVault: secureVault ?? _FakeSecureVault(),
    vpnTunnel: vpnTunnel ?? StubVpnTunnel(),
  );
}

void main() {
  testWidgets('First connect activates, fetches config, then connects', (
    WidgetTester tester,
  ) async {
    final api = _FakeActivationApi();
    final configApi = _FakeVpnConfigApi();
    final vault = _FakeSecureVault();
    final tunnel = StubVpnTunnel();
    await tester.pumpWidget(
      _app(
        activationApi: api,
        vpnConfigApi: configApi,
        secureVault: vault,
        vpnTunnel: tunnel,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Подключиться'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.power_settings_new));
    await tester.pumpAndSettle();

    expect(find.text('Введите ключ доступа'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'BRATAN-TESTKEY01');
    await tester.tap(find.widgetWithText(TextButton, 'Подключиться'));
    await tester.pumpAndSettle();

    expect(api.calls, 1);
    expect(configApi.calls, 1);
    expect(await tunnel.isRunning(), isTrue);
    expect(vault.store[SecureVaultKeys.vpnConfig], isNotNull);
    expect(find.text('Подключено'), findsOneWidget);
  });

  testWidgets('Shows API error and stays on dialog', (WidgetTester tester) async {
    final api = _FakeActivationApi(
      failWith: ActivationException('Ключ не найден.'),
    );
    await tester.pumpWidget(_app(activationApi: api));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.power_settings_new));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'BAD-KEY');
    await tester.tap(find.widgetWithText(TextButton, 'Подключиться'));
    await tester.pumpAndSettle();

    expect(find.text('Ключ не найден.'), findsOneWidget);
    expect(find.text('Введите ключ доступа'), findsOneWidget);
    expect(find.text('Подключено'), findsNothing);
  });

  testWidgets('Shows config error after activation', (WidgetTester tester) async {
    final api = _FakeActivationApi();
    final configApi = _FakeVpnConfigApi(
      failWith: VpnConfigException('Не удалось получить конфигурацию VPN.'),
    );
    final vault = _FakeSecureVault();
    await tester.pumpWidget(
      _app(activationApi: api, vpnConfigApi: configApi, secureVault: vault),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.power_settings_new));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'BRATAN-TESTKEY01');
    await tester.tap(find.widgetWithText(TextButton, 'Подключиться'));
    await tester.pumpAndSettle();

    expect(api.calls, 1);
    expect(configApi.calls, 1);
    expect(find.text('Не удалось получить конфигурацию VPN.'), findsOneWidget);
    expect(find.text('Введите ключ доступа'), findsOneWidget);
    expect(find.text('Подключено'), findsNothing);
  });

  testWidgets('After activation connect works without dialog', (
    WidgetTester tester,
  ) async {
    final api = _FakeActivationApi();
    final checkApi = _FakeAccessCheckApi();
    await tester.pumpWidget(
      _app(activationApi: api, accessCheckApi: checkApi),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.power_settings_new));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'BRATAN-TESTKEY01');
    await tester.tap(find.widgetWithText(TextButton, 'Подключиться'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.power_settings_new));
    await tester.pumpAndSettle();
    expect(find.text('Подключиться'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.power_settings_new));
    await tester.pumpAndSettle();

    expect(find.text('Введите ключ доступа'), findsNothing);
    expect(find.text('Подключено'), findsOneWidget);
    expect(api.calls, 1);
    expect(checkApi.calls, greaterThanOrEqualTo(1));
  });

  testWidgets('Restores activation from vault when access is valid', (
    WidgetTester tester,
  ) async {
    final api = _FakeActivationApi();
    final checkApi = _FakeAccessCheckApi();
    final vault = _FakeSecureVault();
    vault.store[SecureVaultKeys.activated] = 'true';
    vault.store[SecureVaultKeys.vpnIp] = '10.8.0.2';
    vault.store[SecureVaultKeys.accessKey] = 'BRATAN-TESTKEY01';
    vault.store[SecureVaultKeys.vpnPrivateKey] =
        'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';
    vault.store[SecureVaultKeys.vpnPublicKey] =
        'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=';
    vault.store[SecureVaultKeys.vpnConfig] = jsonEncode(_sampleVpnConfig());

    await tester.pumpWidget(
      _app(activationApi: api, accessCheckApi: checkApi, secureVault: vault),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.power_settings_new));
    await tester.pumpAndSettle();

    expect(find.text('Введите ключ доступа'), findsNothing);
    expect(find.text('Подключено'), findsOneWidget);
    expect(api.calls, 0);
    expect(checkApi.calls, greaterThanOrEqualTo(1));
  });

  testWidgets('Revoked access clears session without status text', (
    WidgetTester tester,
  ) async {
    final checkApi = _FakeAccessCheckApi(status: AccessCheckStatus.revoked);
    final vault = _FakeSecureVault();
    vault.store[SecureVaultKeys.activated] = 'true';
    vault.store[SecureVaultKeys.vpnIp] = '10.8.0.2';
    vault.store[SecureVaultKeys.accessKey] = 'BRATAN-TESTKEY01';
    vault.store[SecureVaultKeys.vpnConfig] = jsonEncode(_sampleVpnConfig());

    await tester.pumpWidget(
      _app(accessCheckApi: checkApi, secureVault: vault),
    );
    await tester.pumpAndSettle();

    expect(find.text('Доступ заблокирован'), findsNothing);
    expect(find.text('Подключиться'), findsOneWidget);
    expect(vault.store[SecureVaultKeys.activated], isNull);
    expect(vault.store[SecureVaultKeys.vpnConfig], isNull);
    expect(vault.store[SecureVaultKeys.accessKey], isNull);

    await tester.tap(find.byIcon(Icons.power_settings_new));
    await tester.pumpAndSettle();
    expect(find.text('Введите ключ доступа'), findsOneWidget);
  });

  testWidgets('Connect blocked when access revoked', (WidgetTester tester) async {
    final checkApi = _FakeAccessCheckApi();
    final vault = _FakeSecureVault();
    await tester.pumpWidget(
      _app(accessCheckApi: checkApi, secureVault: vault),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.power_settings_new));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'BRATAN-TESTKEY01');
    await tester.tap(find.widgetWithText(TextButton, 'Подключиться'));
    await tester.pumpAndSettle();
    expect(find.text('Подключено'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.power_settings_new));
    await tester.pumpAndSettle();
    expect(find.text('Подключиться'), findsOneWidget);

    checkApi.status = AccessCheckStatus.revoked;
    await tester.tap(find.byIcon(Icons.power_settings_new));
    await tester.pumpAndSettle();

    expect(find.text('Подключено'), findsNothing);
    expect(find.text('Доступ заблокирован'), findsNothing);
    expect(find.text('Подключиться'), findsOneWidget);
    expect(vault.store[SecureVaultKeys.activated], isNull);
  });

  testWidgets('Drops to disconnected when tunnel dies mid-session', (
    WidgetTester tester,
  ) async {
    final vault = _FakeSecureVault();
    final tunnel = StubVpnTunnel();
    await tester.pumpWidget(_app(secureVault: vault, vpnTunnel: tunnel));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.power_settings_new));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'BRATAN-TESTKEY01');
    await tester.tap(find.widgetWithText(TextButton, 'Подключиться'));
    await tester.pumpAndSettle();
    expect(find.text('Подключено'), findsOneWidget);

    tunnel.simulateDrop();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    expect(find.text('Подключено'), findsNothing);
    expect(find.text('Подключиться'), findsOneWidget);
    expect(await tunnel.isRunning(), isFalse);
  });
}
