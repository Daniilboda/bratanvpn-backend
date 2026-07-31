import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'package:client/services/vpn_tunnel.dart';
import 'package:client/services/windows_named_pipe.dart';
import 'package:client/services/windows_process_hidden.dart';

/// Windows tunnel via BratanVPN helper service + sidecared AmneziaWG.
///
/// First connect may show one UAC prompt to install [BratanVpnHelper].
/// Later start/stop go through a named pipe — no elevation.
class WindowsVpnTunnel implements VpnTunnel {
  WindowsVpnTunnel({
    this.tunnelName = 'bratanvpn',
  });

  final String tunnelName;

  static const String _helperService = 'BratanVpnHelper';
  static const String _pipePath = r'\\.\pipe\BratanVpnHelper';
  static const String _scExe = r'C:\Windows\System32\sc.exe';

  final WindowsNamedPipeClient _pipe = WindowsNamedPipeClient(_pipePath);

  File? _confFile;

  @override
  Future<void> start({required String confText}) async {
    final confFile = await _writeConfFile(confText);
    _confFile = confFile;

    await _ensureHelperReady();

    final resp = await _pipeCommand('START ${confFile.path}');
    if (!_isOk(resp)) {
      throw VpnTunnelException(
        _userFacingPipeError(resp),
        detail: resp.trim(),
      );
    }
    // Helper already waits until the tunnel service is RUNNING before OK.
  }

  @override
  Future<void> stop() async {
    try {
      if (await _helperReachable()) {
        final resp = await _pipeCommand('STOP');
        if (!_isOk(resp) && !_isAlreadyStopped(resp)) {
          throw VpnTunnelException(
            _userFacingPipeError(resp),
            detail: resp.trim(),
          );
        }
      }
    } finally {
      await _deleteConfFile();
    }
  }

  @override
  Future<bool> isRunning() async {
    // Prefer helper pipe — no console window, no sc.exe.
    if (await _helperReachable()) {
      try {
        final resp = await _pipe.transact('STATUS').timeout(
          const Duration(milliseconds: 800),
        );
        return resp.trim().toUpperCase() == 'RUNNING';
      } on Object {
        // Fall through to sc query.
      }
    }

    final result = await runHidden(
      _scExe,
      ['query', 'AmneziaWGTunnel\$$tunnelName'],
    );
    if (result.exitCode != 0) {
      return false;
    }
    return _combinedOutput(result).toUpperCase().contains('RUNNING');
  }

  Future<void> _ensureHelperReady() async {
    if (await _helperReachable()) {
      return;
    }

    await runHidden(_scExe, ['start', _helperService]);
    if (await _waitHelperReachable()) {
      return;
    }

    await _elevateInstallHelper();
    if (!await _waitHelperReachable()) {
      throw VpnTunnelException(
        'Не удалось установить компонент VPN. '
        'Подтвердите запрос Windows (UAC) и попробуйте снова.',
      );
    }
  }

  Future<void> _elevateInstallHelper() async {
    final helper = await _resolveHelperExe();
    late final int exitCode;
    try {
      exitCode = await elevateRunHidden(helper, 'install');
    } on Object {
      throw VpnTunnelException('Не удалось установить компонент VPN.');
    }

    if (exitCode == 0) {
      return;
    }
    // ERROR_CANCELLED = 1223 — user dismissed UAC.
    if (exitCode == 1223) {
      throw VpnTunnelException(
        'Нужно разрешить установку VPN-компонента в окне Windows.',
      );
    }
    throw VpnTunnelException('Не удалось установить компонент VPN.');
  }

  Future<String> _resolveHelperExe() async {
    final candidates = <String>[
      _helperNextToExe(),
      r'C:\ProgramData\BratanVPN\bratanvpn_helper.exe',
    ];
    for (final path in candidates) {
      if (path.isNotEmpty && await File(path).exists()) {
        return path;
      }
    }
    throw VpnTunnelException(
      'Компонент VPN не найден в приложении. '
      'Соберите клиент заново или обратитесь в поддержку.',
    );
  }

  String _helperNextToExe() {
    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      return '$exeDir${Platform.pathSeparator}bratanvpn_helper.exe';
    } on Object {
      return '';
    }
  }

  Future<bool> _helperReachable() async {
    try {
      final resp = await _pipe.transact('PING').timeout(
        const Duration(milliseconds: 800),
      );
      return resp.trim().toUpperCase() == 'PONG';
    } on Object {
      return false;
    }
  }

  Future<bool> _waitHelperReachable({
    int attempts = 20,
    Duration delay = const Duration(milliseconds: 250),
  }) async {
    for (var i = 0; i < attempts; i++) {
      if (await _helperReachable()) {
        return true;
      }
      await Future<void>.delayed(delay);
    }
    return false;
  }

  Future<String> _pipeCommand(String command) async {
    try {
      return await _pipe.transact(command);
    } on Object catch (error) {
      throw VpnTunnelException(
        'Нет связи с VPN-службой (${error.runtimeType}).',
        detail: error.toString(),
      );
    }
  }

  bool _isOk(String response) {
    return response.trim().toUpperCase().startsWith('OK');
  }

  bool _isAlreadyStopped(String response) {
    final low = response.toLowerCase();
    return low.contains('cannot find') ||
        low.contains('not found') ||
        low.contains('does not exist');
  }

  String _userFacingPipeError(String response) {
    final low = response.toLowerCase();
    if (_looksLikeElevationError(low)) {
      return 'Нужно разрешить установку VPN-компонента в окне Windows.';
    }
    return 'Не удалось запустить VPN.';
  }

  Future<File> _writeConfFile(String confText) async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}${Platform.pathSeparator}vpn');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final file = File('${dir.path}${Platform.pathSeparator}$tunnelName.conf');
    await file.writeAsString(confText, flush: true);
    return file;
  }

  Future<void> _deleteConfFile() async {
    final file = _confFile;
    _confFile = null;
    if (file == null) {
      return;
    }
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } on Object {
      // Best-effort cleanup.
    }
  }

  String _combinedOutput(ProcessResult result) {
    return '${result.stdout}\n${result.stderr}'.trim();
  }

  bool _looksLikeElevationError(String text) {
    return text.contains('canceled') ||
        text.contains('cancelled') ||
        text.contains('отмен') ||
        text.contains('elevation') ||
        text.contains('1223');
  }
}
