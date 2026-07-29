package com.bratanvpn.client.vpn

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.system.OsConstants
import android.util.Log
import com.bratanvpn.client.MainActivity
import com.bratanvpn.client.R
import com.getkeepsafe.relinker.ReLinker
import org.amnezia.awg.GoBackend as AwgNative
import org.amnezia.awg.config.Config
import org.amnezia.awg.config.InetNetwork
import org.amnezia.awg.config.Peer
import java.io.ByteArrayInputStream
import java.nio.charset.StandardCharsets
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference

/**
 * System VPN + AmneziaWG userspace engine.
 *
 * Flow: parse conf → Builder.establish() → awgTurnOn(TUN fd, config).
 */
class BratanVpnService : VpnService() {
    private var tun: ParcelFileDescriptor? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val conf = intent.getStringExtra(EXTRA_CONF).orEmpty()
                // Foreground must start immediately after startForegroundService().
                startForeground(NOTIFICATION_ID, buildNotification())
                worker.execute {
                    try {
                        startTunnel(conf)
                        signalStart(true)
                    } catch (e: Exception) {
                        Log.e(TAG, "VPN start failed: ${e.message}", e)
                        stopTunnelInternal()
                        running.set(false)
                        signalStart(false)
                        stopForegroundCompat()
                        stopSelf()
                    }
                }
            }
            ACTION_STOP -> {
                worker.execute {
                    stopTunnelInternal()
                    running.set(false)
                    signalStop()
                    stopForegroundCompat()
                    stopSelf()
                }
            }
            else -> stopSelf()
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        stopTunnelInternal()
        running.set(false)
        super.onDestroy()
    }

    private fun startTunnel(confText: String) {
        if (confText.isBlank()) {
            throw IllegalArgumentException("Пустая VPN-конфигурация")
        }

        ensureNativeLoaded()

        val config = Config.parse(
            ByteArrayInputStream(confText.toByteArray(StandardCharsets.UTF_8)),
        )
        resolvePeerEndpoints(config)

        stopTunnelInternal()

        val builder = Builder()
            .setSession(TUNNEL_NAME)
            .setMtu(config.getInterface().mtu.orElse(1280))
            .setBlocking(true)

        for (addr: InetNetwork in config.getInterface().addresses) {
            builder.addAddress(addr.address, addr.mask)
        }
        for (dns in config.getInterface().dnsServers) {
            val host = dns.hostAddress ?: continue
            builder.addDnsServer(host)
        }
        for (domain in config.getInterface().dnsSearchDomains) {
            builder.addSearchDomain(domain)
        }

        var sawDefaultRoute = false
        for (peer: Peer in config.peers) {
            for (addr: InetNetwork in peer.allowedIps) {
                if (addr.mask == 0) {
                    sawDefaultRoute = true
                }
                builder.addRoute(addr.address, addr.mask)
            }
        }

        if (!(sawDefaultRoute && config.peers.size == 1)) {
            builder.allowFamily(OsConstants.AF_INET)
            builder.allowFamily(OsConstants.AF_INET6)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            builder.setMetered(false)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            setUnderlyingNetworks(null)
        }

        val established = builder.establish()
            ?: throw IllegalStateException("Система отклонила VPN-интерфейс")

        val goConfig = config.toAwgQuickStringResolved(
            /* includeScripts = */ false,
            /* includeProxies = */ false,
            /* preferIpv4 = */ true,
            this,
        )
        val uapiPath = dataDir.absolutePath
        val fd = established.detachFd()
        // Ownership of fd moved to Go; keep ParcelFileDescriptor only if needed — close wrapper.
        try {
            established.close()
        } catch (_: Exception) {
        }
        tun = null

        Log.i(TAG, "Starting AmneziaWG ${AwgNative.awgVersion()}")
        val handle = AwgNative.awgTurnOn(TUNNEL_NAME, fd, goConfig, uapiPath)
        if (handle < 0) {
            throw IllegalStateException("AmneziaWG не запустился (код $handle)")
        }
        tunnelHandle.set(handle)

        protect(AwgNative.awgGetSocketV4(handle))
        protect(AwgNative.awgGetSocketV6(handle))

        running.set(true)
        Log.i(TAG, "AmneziaWG tunnel up (handle=$handle)")
    }

    private fun resolvePeerEndpoints(config: Config) {
        val retries = 5
        for (attempt in 0 until retries) {
            var failed: String? = null
            for (peer in config.peers) {
                val ep = peer.endpoint.orElse(null) ?: continue
                if (!ep.getResolved(true, this).isPresent) {
                    failed = ep.host
                }
            }
            if (failed == null) return
            if (attempt == retries - 1) {
                throw IllegalStateException("Не удалось разрешить DNS: $failed")
            }
            Log.w(TAG, "DNS \"$failed\" failed, retry ${attempt + 1}/$retries")
            Thread.sleep(500L * (1L shl attempt))
        }
    }

    private fun stopTunnelInternal() {
        val handle = tunnelHandle.getAndSet(-1)
        if (handle >= 0) {
            try {
                AwgNative.awgTurnOff(handle)
            } catch (e: Exception) {
                Log.w(TAG, "awgTurnOff: ${e.message}")
            }
        }
        try {
            tun?.close()
        } catch (_: Exception) {
        }
        tun = null
    }

    private fun ensureNativeLoaded() {
        if (nativeLoaded.get()) return
        synchronized(nativeLock) {
            if (nativeLoaded.get()) return
            ReLinker.loadLibrary(this, "am-go")
            nativeLoaded.set(true)
        }
    }

    private fun stopForegroundCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
    }

    private fun buildNotification(): Notification {
        ensureChannel()
        val launch = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setContentTitle("BratanVPN")
            .setContentText("VPN подключён")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(launch)
            .setOngoing(true)
            .setCategory(Notification.CATEGORY_SERVICE)
            .build()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "BratanVPN",
            NotificationManager.IMPORTANCE_LOW,
        )
        manager.createNotificationChannel(channel)
    }

    companion object {
        const val ACTION_START = "com.bratanvpn.client.vpn.START"
        const val ACTION_STOP = "com.bratanvpn.client.vpn.STOP"
        const val EXTRA_CONF = "conf"

        private const val TAG = "BratanVpnService"
        private const val CHANNEL_ID = "bratanvpn_vpn"
        private const val NOTIFICATION_ID = 42
        private const val TUNNEL_NAME = "bratanvpn"

        private val worker = Executors.newSingleThreadExecutor()
        private val running = AtomicBoolean(false)
        private val tunnelHandle = AtomicInteger(-1)
        private val startLatch = AtomicReference<CountDownLatch?>(null)
        private val startOk = AtomicBoolean(false)
        private val stopLatch = AtomicReference<CountDownLatch?>(null)
        private val nativeLoaded = AtomicBoolean(false)
        private val nativeLock = Any()

        fun isRunning(): Boolean = running.get()

        fun armStartWait(): CountDownLatch {
            val latch = CountDownLatch(1)
            startOk.set(false)
            startLatch.set(latch)
            return latch
        }

        fun awaitStart(latch: CountDownLatch, timeoutMs: Long): Boolean {
            val finished = latch.await(timeoutMs, TimeUnit.MILLISECONDS)
            return finished && startOk.get() && running.get()
        }

        private fun signalStart(ok: Boolean) {
            startOk.set(ok)
            startLatch.getAndSet(null)?.countDown()
        }

        /** Arm before [ACTION_STOP] so Flutter can wait until the tunnel is down. */
        fun armStopWait(): CountDownLatch {
            val latch = CountDownLatch(1)
            stopLatch.set(latch)
            if (!running.get()) {
                latch.countDown()
            }
            return latch
        }

        fun awaitStop(latch: CountDownLatch, timeoutMs: Long): Boolean {
            return latch.await(timeoutMs, TimeUnit.MILLISECONDS)
        }

        private fun signalStop() {
            stopLatch.getAndSet(null)?.countDown()
        }
    }
}
