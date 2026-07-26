import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:client/services/api_config.dart';

class VpnConfigException implements Exception {
  VpnConfigException(this.userMessage, {this.statusCode});

  final String userMessage;
  final int? statusCode;

  @override
  String toString() => userMessage;
}

class VpnConfigApi {
  VpnConfigApi({http.Client? client, this.baseUrl = apiBaseUrl})
    : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;

  Future<Map<String, dynamic>> fetchConfig({
    required String accessKey,
    required String deviceId,
  }) async {
    final uri = Uri.parse('$baseUrl/api/v1/vpn/config').replace(
      queryParameters: {
        'access_key': accessKey,
        'device_id': deviceId,
      },
    );

    late final http.Response response;
    try {
      response = await _client.get(uri).timeout(const Duration(seconds: 30));
    } on Exception {
      throw VpnConfigException('Проверьте подключение к интернету.');
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) {
        throw VpnConfigException('Сервер временно недоступен.');
      }
      return body;
    }

    throw VpnConfigException(
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
      if (detail.contains('not found')) {
        return 'Ключ не найден.';
      }
      if (detail.contains('not activated')) {
        return 'Ключ ещё не активирован.';
      }
      if (detail.contains('not provisioned')) {
        return 'VPN ещё не настроен для этого ключа.';
      }
    }

    return switch (statusCode) {
      404 => 'Ключ не найден.',
      403 => 'Доступ заблокирован.',
      409 => 'VPN ещё не настроен для этого ключа.',
      502 => 'Сервер временно недоступен.',
      _ => 'Не удалось получить конфигурацию VPN.',
    };
  }
}
