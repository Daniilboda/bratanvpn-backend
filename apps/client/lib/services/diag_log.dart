import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Local diagnostic log for manual VPN checks.
///
/// Each [startCheck] creates a **new** file with date/time in the name.
/// Older files are kept. Never write access keys, private keys, or full conf.
class DiagLog {
  DiagLog._();

  static final DiagLog instance = DiagLog._();

  File? _file;
  Future<void> _writeChain = Future<void>.value();
  bool _ended = false;

  /// Absolute path of the current check file, if started.
  String? get currentPath => _file?.path;

  /// Starts a new check log file. Previous files remain on disk.
  Future<String?> startCheck({String reason = 'app_start'}) async {
    try {
      final dir = await _checksDirectory();
      await dir.create(recursive: true);

      final stamp = _fileStamp(DateTime.now());
      final file = File('${dir.path}${Platform.pathSeparator}check_$stamp.log');
      _file = file;
      _ended = false;

      await file.writeAsString(
        '${_lineStamp(DateTime.now())} [INFO] check_started '
        'reason=$reason platform=${_platformLabel()}\n'
        '${_lineStamp(DateTime.now())} [INFO] log_file=${file.path}\n',
        flush: true,
      );

      debugPrint('[BratanVPN diag] log_file=${file.path}');
      return file.path;
    } on Object catch (error) {
      debugPrint('[BratanVPN diag] startCheck failed: $error');
      _file = null;
      return null;
    }
  }

  Future<void> info(String event, [Map<String, Object?> fields = const {}]) {
    return _append('INFO', event, fields);
  }

  Future<void> warn(String event, [Map<String, Object?> fields = const {}]) {
    return _append('WARN', event, fields);
  }

  Future<void> error(String event, [Map<String, Object?> fields = const {}]) {
    return _append('ERROR', event, fields);
  }

  /// Flushes pending lines and writes `check_ended` (flutter `q` / tray quit).
  ///
  /// If no file exists yet, creates one so a quit still leaves a log on disk.
  Future<void> endCheck({String reason = 'quit'}) async {
    if (_ended) {
      return;
    }
    _ended = true;

    if (_file == null) {
      // e.g. quit right after start failure — still create a dated file.
      _ended = false;
      await startCheck(reason: 'quit_$reason');
      _ended = true;
    }

    await info('check_ended', {'reason': reason});
    try {
      await _writeChain;
    } on Object catch (error) {
      debugPrint('[BratanVPN diag] endCheck flush failed: $error');
    }
    debugPrint('[BratanVPN diag] check_ended reason=$reason path=${_file?.path}');
  }

  /// Short opaque device id for logs (never the full uuid if long).
  static String shortDeviceId(String? deviceId) {
    if (deviceId == null || deviceId.isEmpty) {
      return '-';
    }
    if (deviceId.length <= 8) {
      return deviceId;
    }
    return '${deviceId.substring(0, 8)}…';
  }

  Future<Directory> _checksDirectory() async {
    final support = await getApplicationSupportDirectory();
    return Directory(
      '${support.path}${Platform.pathSeparator}diag_checks',
    );
  }

  Future<void> _append(
    String level,
    String event,
    Map<String, Object?> fields,
  ) {
    final file = _file;
    if (file == null) {
      return Future<void>.value();
    }

    final buffer = StringBuffer(_lineStamp(DateTime.now()))
      ..write(' [')
      ..write(level)
      ..write('] ')
      ..write(event);
    for (final entry in fields.entries) {
      final value = entry.value;
      if (value == null) {
        continue;
      }
      buffer
        ..write(' ')
        ..write(entry.key)
        ..write('=')
        ..write(_sanitize(value));
    }
    buffer.writeln();

    final line = buffer.toString();
    debugPrint('[BratanVPN diag] $line'.trimRight());

    _writeChain = _writeChain.then((_) async {
      try {
        await file.writeAsString(line, mode: FileMode.append, flush: true);
      } on Object catch (error) {
        debugPrint('[BratanVPN diag] write failed: $error');
      }
    });
    return _writeChain;
  }

  static String _sanitize(Object value) {
    final raw = value.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    // Never persist access keys even if a caller slips.
    if (RegExp(r'BRATAN-[A-Z0-9]+', caseSensitive: false).hasMatch(raw)) {
      return '<redacted-access-key>';
    }
    if (raw.toLowerCase().contains('privatekey') ||
        raw.toLowerCase().contains('private_key')) {
      return '<redacted>';
    }
    if (raw.length > 200) {
      return '${raw.substring(0, 200)}…';
    }
    return raw;
  }

  static String _fileStamp(DateTime dt) {
    final local = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)}_'
        '${two(local.hour)}-${two(local.minute)}-${two(local.second)}';
  }

  static String _lineStamp(DateTime dt) => dt.toUtc().toIso8601String();

  static String _platformLabel() {
    if (kIsWeb) {
      return 'web';
    }
    if (Platform.isWindows) {
      return 'windows';
    }
    if (Platform.isAndroid) {
      return 'android';
    }
    return Platform.operatingSystem;
  }
}
