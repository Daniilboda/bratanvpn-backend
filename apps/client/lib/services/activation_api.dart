import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:client/services/api_config.dart';

class ActivationSuccess {
  const ActivationSuccess();
}

class ActivationException implements Exception {
  ActivationException(this.userMessage, {this.statusCode});

  final String userMessage;
  final int? statusCode;

  @override
  String toString() => userMessage;
}

class ActivationApi {
  ActivationApi({http.Client? client, this.baseUrl = apiBaseUrl})
    : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;

  /// Binds access key to this device. Does not allocate vpn_ip / peer.
  Future<ActivationSuccess> activate({
    required String accessKey,
    required String deviceId,
    required String vpnPublicKey,
  }) async {
    final uri = Uri.parse('$baseUrl/api/v1/activate');

    late final http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'access_key': accessKey,
              'device_id': deviceId,
              'vpn_public_key': vpnPublicKey,
            }),
          )
          .timeout(const Duration(seconds: 30));
    } on Exception {
      throw ActivationException('Проверьте подключение к интернету.');
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return const ActivationSuccess();
    }

    throw ActivationException(
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
        return 'Ключ отозван. Доступ заблокирован.';
      }
      if (detail.contains('not found')) {
        return 'Ключ не найден.';
      }
    }

    return switch (statusCode) {
      404 => 'Ключ не найден.',
      403 => 'Ключ отозван. Доступ заблокирован.',
      502 => 'Сервер временно недоступен.',
      _ => 'Не удалось активировать ключ.',
    };
  }
}
