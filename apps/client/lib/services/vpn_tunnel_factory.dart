import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:client/services/vpn_tunnel.dart';
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
  // Android native VpnService — next iteration.
  return StubVpnTunnel();
}
