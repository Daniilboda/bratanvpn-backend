import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:client/services/api_config.dart';

/// Result of POST /api/v1/validate.
enum AccessCheckStatus {
  valid,
  revoked,
  notFound,
  deviceMismatch,
  readyToActivate,
  unknown,
}

class AccessCheckException implements Exception {
  AccessCheckException(this.userMessage);

  final String userMessage;

  @override
  String toString() => userMessage;
}

class AccessCheckApi {
  AccessCheckApi({http.Client? client, this.baseUrl = apiBaseUrl})
    : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;

  Future<AccessCheckStatus> check({
    required String accessKey,
    required String deviceId,
  }) async {
    final uri = Uri.parse('$baseUrl/api/v1/validate');

    late final http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'key': accessKey,
              'device_id': deviceId,
            }),
          )
          .timeout(const Duration(seconds: 30));
    } on Exception {
      throw AccessCheckException('Проверьте подключение к интернету.');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AccessCheckException('Сервер временно недоступен.');
    }

    final body = jsonDecode(response.body);
    if (body is! Map<String, dynamic>) {
      return AccessCheckStatus.unknown;
    }

    final status = body['status'] as String?;
    return switch (status) {
      'valid' => AccessCheckStatus.valid,
      'revoked' => AccessCheckStatus.revoked,
      'not_found' => AccessCheckStatus.notFound,
      'device_mismatch' => AccessCheckStatus.deviceMismatch,
      'ready_to_activate' => AccessCheckStatus.readyToActivate,
      _ => AccessCheckStatus.unknown,
    };
  }
}
