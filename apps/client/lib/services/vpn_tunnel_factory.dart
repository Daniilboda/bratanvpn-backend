import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:client/services/vpn_tunnel.dart';
import 'package:client/services/vpn_tunnel_android.dart';
import 'package:client/services/vpn_tunnel_stub.dart';
import 'package:client/services/vpn_tunnel_windows.dart';

/// Creates the platform tunnel implementation.
VpnTunnel createVpnTunnel() {
  if (kIsWeb) {
    return StubVpnTunnel();
  }
  if (Platform.isWindows) {
    return WindowsVpnTunnel();
  }
  if (Platform.isAndroid) {
    return AndroidVpnTunnel();
  }
  return StubVpnTunnel();
}
