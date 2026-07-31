import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:client/services/api_config.dart';

class VpnSessionException implements Exception {
  VpnSessionException(this.userMessage, {this.statusCode});

  final String userMessage;
  final int? statusCode;

  @override
  String toString() => userMessage;
}

class VpnSessionApi {
  VpnSessionApi({http.Client? client, this.baseUrl = apiBaseUrl})
    : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;

  /// Allocates vpn_ip and adds AmneziaWG peer for this device.
  Future<String> connect({
    required String accessKey,
    required String deviceId,
  }) async {
    final uri = Uri.parse('$baseUrl/api/v1/vpn/connect');

    late final http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'access_key': accessKey,
              'device_id': deviceId,
            }),
          )
          .timeout(const Duration(seconds: 30));
    } on Exception catch (error) {
      throw VpnSessionException(
        'Нет связи с API ($baseUrl): ${error.runtimeType}',
      );
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final vpnIp = body['vpn_ip'] as String?;
      if (vpnIp == null || vpnIp.isEmpty) {
        throw VpnSessionException('Сервер временно недоступен.');
      }
      return vpnIp;
    }

    throw VpnSessionException(
      _messageForError(response.statusCode, response.body),
      statusCode: response.statusCode,
    );
  }

  /// Removes peer and clears vpn_ip. Safe to call when already disconnected.
  Future<void> disconnect({
    required String accessKey,
    required String deviceId,
  }) async {
    final uri = Uri.parse('$baseUrl/api/v1/vpn/disconnect');

    late final http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'access_key': accessKey,
              'device_id': deviceId,
            }),
          )
          .timeout(const Duration(seconds: 30));
    } on Exception catch (error) {
      throw VpnSessionException(
        'Нет связи с API ($baseUrl): ${error.runtimeType}',
      );
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }

    throw VpnSessionException(
      _messageForError(response.statusCode, response.body),
      statusCode: response.statusCode,
    );
  }

  String _messageForError(int statusCode, String body) {
    String? detail;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        detail = decoded['detail'] as String?;
      }
    } on FormatException {
      detail = null;
    }

    if (detail != null) {
      if (detail.contains('another device')) {
        return 'Ключ уже активирован на другом устройстве.';
      }
      if (detail.contains('revoked')) {
        return 'Доступ заблокирован.';
      }
      if (detail.contains('not activated')) {
        return 'Ключ не активирован.';
      }
      if (detail.contains('not found')) {
        return 'Ключ не найден.';
      }
    }

    return switch (statusCode) {
      404 => 'Ключ не найден.',
      403 => 'Доступ заблокирован.',
      502 => 'Сервер временно недоступен.',
      _ => 'Не удалось управлять VPN-сессией.',
    };
  }
}
