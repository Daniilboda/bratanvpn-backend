package com.bratanvpn.client

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import android.os.Build
import com.bratanvpn.client.vpn.BratanVpnService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var prepareResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "prepare" -> prepareVpn(result)
                "start" -> {
                    val conf = call.argument<String>("confText")
                    if (conf.isNullOrBlank()) {
                        result.error("INVALID_CONF", "Пустая VPN-конфигурация.", null)
                        return@setMethodCallHandler
                    }
                    startVpn(conf, result)
                }
                "stop" -> stopVpn(result)
                "isRunning" -> result.success(BratanVpnService.isRunning())
                else -> result.notImplemented()
            }
        }
    }

    private fun prepareVpn(result: MethodChannel.Result) {
        val intent = VpnService.prepare(this)
        if (intent == null) {
            result.success(true)
            return
        }
        if (prepareResult != null) {
            result.error("BUSY", "Запрос разрешения VPN уже идёт.", null)
            return
        }
        prepareResult = result
        @Suppress("DEPRECATION")
        startActivityForResult(intent, REQUEST_VPN_PREPARE)
    }

    private fun startVpn(confText: String, result: MethodChannel.Result) {
        val prepareIntent = VpnService.prepare(this)
        if (prepareIntent != null) {
            result.error(
                "VPN_PERMISSION_REQUIRED",
                "Нужно разрешение VPN. Разрешите доступ и повторите.",
                null,
            )
            return
        }

        val intent = Intent(this, BratanVpnService::class.java).apply {
            action = BratanVpnService.ACTION_START
            putExtra(BratanVpnService.EXTRA_CONF, confText)
        }
        try {
            // Wait off the main thread: service onStartCommand also runs on main.
            val latch = BratanVpnService.armStartWait()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
            Thread {
                val ok = BratanVpnService.awaitStart(latch, 20_000L)
                runOnUiThread {
                    if (ok) {
                        result.success(null)
                    } else {
                        result.error(
                            "VPN_START_FAILED",
                            "Не удалось запустить VPN-интерфейс.",
                            null,
                        )
                    }
                }
            }.start()
        } catch (e: Exception) {
            result.error("VPN_START_FAILED", e.message ?: "Не удалось запустить VPN.", null)
        }
    }

    private fun stopVpn(result: MethodChannel.Result) {
        val latch = BratanVpnService.armStopWait()
        val intent = Intent(this, BratanVpnService::class.java).apply {
            action = BratanVpnService.ACTION_STOP
        }
        try {
            startService(intent)
        } catch (e: Exception) {
            result.error("VPN_STOP_FAILED", e.message ?: "Не удалось остановить VPN.", null)
            return
        }
        Thread {
            BratanVpnService.awaitStop(latch, 5_000L)
            runOnUiThread { result.success(null) }
        }.start()
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_VPN_PREPARE) return
        val pending = prepareResult
        prepareResult = null
        pending?.success(resultCode == Activity.RESULT_OK)
    }

    companion object {
        private const val CHANNEL = "com.bratanvpn.client/vpn"
        private const val REQUEST_VPN_PREPARE = 1001
    }
}
