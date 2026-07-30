import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// Keep process handle after ShellExecuteEx (not always exported by win32).
const int _seeMaskNocloseprocess = 0x00000040;

/// Runs a Windows console tool without flashing a console window.
///
/// Uses [CREATE_NO_WINDOW] + redirected stdout/stderr pipes.
Future<ProcessResult> runHidden(
  String executable,
  List<String> arguments,
) async {
  if (!Platform.isWindows) {
    return Process.run(executable, arguments, runInShell: false);
  }
  return _runHiddenSync(executable, arguments);
}

ProcessResult _runHiddenSync(String executable, List<String> arguments) {
  final commandLine = _buildCommandLine(executable, arguments);
  final commandLinePtr = commandLine.toNativeUtf16();

  final stdoutRead = calloc<HANDLE>();
  final stdoutWrite = calloc<HANDLE>();
  final stderrRead = calloc<HANDLE>();
  final stderrWrite = calloc<HANDLE>();
  final sa = calloc<SECURITY_ATTRIBUTES>();
  final si = calloc<STARTUPINFO>();
  final pi = calloc<PROCESS_INFORMATION>();

  try {
    sa.ref
      ..nLength = sizeOf<SECURITY_ATTRIBUTES>()
      ..bInheritHandle = TRUE
      ..lpSecurityDescriptor = nullptr;

    if (CreatePipe(stdoutRead, stdoutWrite, sa, 0) == FALSE) {
      throw WindowsException(GetLastError());
    }
    if (CreatePipe(stderrRead, stderrWrite, sa, 0) == FALSE) {
      throw WindowsException(GetLastError());
    }
    // Child should not inherit the read ends.
    SetHandleInformation(stdoutRead.value, HANDLE_FLAG_INHERIT, 0);
    SetHandleInformation(stderrRead.value, HANDLE_FLAG_INHERIT, 0);

    si.ref
      ..cb = sizeOf<STARTUPINFO>()
      ..dwFlags = STARTF_USESTDHANDLES
      ..hStdInput = INVALID_HANDLE_VALUE
      ..hStdOutput = stdoutWrite.value
      ..hStdError = stderrWrite.value;

    final ok = CreateProcess(
      nullptr,
      commandLinePtr,
      nullptr,
      nullptr,
      TRUE,
      CREATE_NO_WINDOW,
      nullptr,
      nullptr,
      si,
      pi,
    );
    if (ok == FALSE) {
      throw WindowsException(GetLastError());
    }

    CloseHandle(stdoutWrite.value);
    CloseHandle(stderrWrite.value);
    stdoutWrite.value = INVALID_HANDLE_VALUE;
    stderrWrite.value = INVALID_HANDLE_VALUE;

    final stdoutBytes = _readPipeToEnd(stdoutRead.value);
    final stderrBytes = _readPipeToEnd(stderrRead.value);

    WaitForSingleObject(pi.ref.hProcess, INFINITE);
    final exitCodePtr = calloc<DWORD>();
    try {
      GetExitCodeProcess(pi.ref.hProcess, exitCodePtr);
      final exitCode = exitCodePtr.value;
      return ProcessResult(
        pi.ref.dwProcessId,
        exitCode,
        utf8.decode(stdoutBytes, allowMalformed: true),
        utf8.decode(stderrBytes, allowMalformed: true),
      );
    } finally {
      calloc.free(exitCodePtr);
    }
  } finally {
    if (stdoutWrite.value != INVALID_HANDLE_VALUE) {
      CloseHandle(stdoutWrite.value);
    }
    if (stderrWrite.value != INVALID_HANDLE_VALUE) {
      CloseHandle(stderrWrite.value);
    }
    CloseHandle(stdoutRead.value);
    CloseHandle(stderrRead.value);
    if (pi.ref.hProcess != NULL) {
      CloseHandle(pi.ref.hProcess);
    }
    if (pi.ref.hThread != NULL) {
      CloseHandle(pi.ref.hThread);
    }
    calloc.free(commandLinePtr);
    calloc.free(stdoutRead);
    calloc.free(stdoutWrite);
    calloc.free(stderrRead);
    calloc.free(stderrWrite);
    calloc.free(sa);
    calloc.free(si);
    calloc.free(pi);
  }
}

Uint8List _readPipeToEnd(int handle) {
  final buffer = <int>[];
  final chunk = calloc<Uint8>(4096);
  final bytesRead = calloc<DWORD>();
  try {
    while (true) {
      final ok = ReadFile(handle, chunk, 4096, bytesRead, nullptr);
      if (ok == FALSE || bytesRead.value == 0) {
        break;
      }
      for (var i = 0; i < bytesRead.value; i++) {
        buffer.add(chunk[i]);
      }
    }
  } finally {
    calloc.free(chunk);
    calloc.free(bytesRead);
  }
  return Uint8List.fromList(buffer);
}

String _buildCommandLine(String executable, List<String> arguments) {
  final parts = <String>[_quoteWinArg(executable), ...arguments.map(_quoteWinArg)];
  return parts.join(' ');
}

String _quoteWinArg(String arg) {
  if (arg.isEmpty) {
    return '""';
  }
  final needsQuotes = arg.contains(' ') || arg.contains('\t') || arg.contains('"');
  if (!needsQuotes) {
    return arg;
  }
  final escaped = arg.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
  return '"$escaped"';
}

/// Elevates [exePath] with UAC (runas) without a PowerShell console flash.
Future<int> elevateRunHidden(String exePath, String arguments) async {
  if (!Platform.isWindows) {
    throw UnsupportedError('elevateRunHidden is Windows-only');
  }

  final info = calloc<SHELLEXECUTEINFO>();
  final filePtr = exePath.toNativeUtf16();
  final paramsPtr = arguments.toNativeUtf16();
  final verbPtr = 'runas'.toNativeUtf16();
  try {
    info.ref
      ..cbSize = sizeOf<SHELLEXECUTEINFO>()
      ..fMask = _seeMaskNocloseprocess
      ..hwnd = NULL
      ..lpVerb = verbPtr
      ..lpFile = filePtr
      ..lpParameters = paramsPtr
      ..lpDirectory = nullptr
      ..nShow = SW_HIDE;

    final ok = ShellExecuteEx(info);
    if (ok == FALSE) {
      final err = GetLastError();
      // User cancelled UAC.
      if (err == ERROR_CANCELLED) {
        return err;
      }
      throw WindowsException(err);
    }

    final process = info.ref.hProcess;
    if (process == NULL || process == 0) {
      return 1;
    }
    WaitForSingleObject(process, INFINITE);
    final exitCodePtr = calloc<DWORD>();
    try {
      GetExitCodeProcess(process, exitCodePtr);
      return exitCodePtr.value;
    } finally {
      calloc.free(exitCodePtr);
      CloseHandle(process);
    }
  } finally {
    calloc.free(info);
    calloc.free(filePtr);
    calloc.free(paramsPtr);
    calloc.free(verbPtr);
  }
}
