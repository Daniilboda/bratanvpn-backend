import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// Minimal Windows named-pipe client (byte stream, line protocol).
///
/// Avoids spawning PowerShell for every VPN helper call (~1–2s each).
class WindowsNamedPipeClient {
  WindowsNamedPipeClient(this.pipePath);

  /// e.g. `\\.\pipe\BratanVpnHelper`
  final String pipePath;

  /// Sends [command] plus newline, returns one response line (without `\n`).
  Future<String> transact(
    String command, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (!Platform.isWindows) {
      throw UnsupportedError('named pipes are Windows-only');
    }
    final path = pipePath;
    return Isolate.run(() => _transactSync(path, command)).timeout(timeout);
  }

  static String _transactSync(String pipePath, String command) {
    final pathPtr = pipePath.toNativeUtf16();
    final handle = CreateFile(
      pathPtr,
      GENERIC_READ | GENERIC_WRITE,
      0,
      nullptr,
      OPEN_EXISTING,
      FILE_ATTRIBUTE_NORMAL,
      NULL,
    );
    calloc.free(pathPtr);

    if (handle == INVALID_HANDLE_VALUE) {
      throw WindowsException(GetLastError());
    }

    try {
      final payload = Uint8List.fromList(utf8.encode('$command\n'));
      final writeBuf = calloc<Uint8>(payload.length);
      final bytesWritten = calloc<DWORD>();
      try {
        for (var i = 0; i < payload.length; i++) {
          writeBuf[i] = payload[i];
        }
        final ok = WriteFile(
          handle,
          writeBuf,
          payload.length,
          bytesWritten,
          nullptr,
        );
        if (ok == FALSE) {
          throw WindowsException(GetLastError());
        }
      } finally {
        calloc.free(writeBuf);
        calloc.free(bytesWritten);
      }

      final response = StringBuffer();
      final readBuf = calloc<Uint8>(1);
      final bytesRead = calloc<DWORD>();
      try {
        while (true) {
          final ok = ReadFile(handle, readBuf, 1, bytesRead, nullptr);
          if (ok == FALSE || bytesRead.value == 0) {
            throw WindowsException(GetLastError());
          }
          final unit = readBuf[0];
          if (unit == 10 /* \n */) {
            break;
          }
          if (unit != 13 /* \r */) {
            response.writeCharCode(unit);
          }
          if (response.length > 4096) {
            throw StateError('helper response too long');
          }
        }
      } finally {
        calloc.free(readBuf);
        calloc.free(bytesRead);
      }

      final text = response.toString().trim();
      if (text.isEmpty) {
        throw StateError('empty helper response');
      }
      return text;
    } finally {
      CloseHandle(handle);
    }
  }
}
