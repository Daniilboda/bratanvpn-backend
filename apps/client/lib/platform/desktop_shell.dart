import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

/// Windows close-to-tray behavior (spec: крестик → трей, выход из трея → quit).
///
/// No-op on non-Windows platforms and in widget tests (do not call [init]).
class DesktopShell with WindowListener, TrayListener {
  DesktopShell();

  static const String _trayIconAsset = 'assets/tray_icon.ico';

  /// Called before process exit (tray «Выход»). Should stop VPN.
  Future<void> Function()? beforeQuit;

  bool _initialized = false;
  bool _quitting = false;

  Future<void> init() async {
    if (!Platform.isWindows || kIsWeb || _initialized) {
      return;
    }

    await windowManager.ensureInitialized();

    const options = WindowOptions(
      size: Size(380, 720),
      minimumSize: Size(320, 560),
      center: true,
      backgroundColor: Colors.black,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
      title: 'BratanVPN',
    );

    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.setPreventClose(true);
      await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
      // Taskbar / Alt-Tab icon (asset path relative to Flutter assets).
      await windowManager.setIcon(_trayIconAsset);
      await windowManager.show();
      await windowManager.focus();
    });

    windowManager.addListener(this);
    trayManager.addListener(this);

    await trayManager.setIcon(_trayIconAsset);
    await trayManager.setToolTip('BratanVPN');
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: 'show', label: 'Открыть BratanVPN'),
          MenuItem.separator(),
          MenuItem(key: 'quit', label: 'Выход'),
        ],
      ),
    );

    _initialized = true;
  }

  Future<void> showWindow() async {
    await windowManager.show();
    await windowManager.setSkipTaskbar(false);
    await windowManager.focus();
  }

  Future<void> hideToTray() async {
    await windowManager.hide();
    await windowManager.setSkipTaskbar(true);
  }

  Future<void> quit() async {
    if (_quitting) {
      return;
    }
    _quitting = true;

    try {
      await beforeQuit?.call();
    } on Object {
      // Best-effort VPN stop; still exit.
    }

    if (_initialized) {
      windowManager.removeListener(this);
      trayManager.removeListener(this);
      try {
        await trayManager.destroy();
      } on Object {
        // Ignore tray cleanup errors.
      }
      await windowManager.setPreventClose(false);
    }

    await windowManager.destroy();
  }

  @override
  void onWindowClose() {
    // Крестик: спрятать в трей, VPN не трогать.
    hideToTray();
  }

  @override
  void onTrayIconMouseDown() {
    showWindow();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        showWindow();
        break;
      case 'quit':
        quit();
        break;
    }
  }
}
