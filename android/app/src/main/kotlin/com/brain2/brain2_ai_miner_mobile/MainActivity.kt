package com.brain2.brain2_ai_miner_mobile

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val shareChannelName = "global_context/share_receiver"
    private lateinit var shareChannel: MethodChannel
    private var pendingShare: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        captureShare(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureShare(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        shareChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            shareChannelName
        )
        shareChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "takePendingShare" -> {
                    val value = pendingShare
                    pendingShare = null
                    result.success(value)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun captureShare(intent: Intent?) {
        if (intent?.action != Intent.ACTION_SEND) return
        if (!(intent.type ?: "").startsWith("text/")) return
        val shared = intent.getStringExtra(Intent.EXTRA_TEXT)?.trim()
        if (shared.isNullOrEmpty()) return
        pendingShare = shared
        if (::shareChannel.isInitialized) {
            shareChannel.invokeMethod("sharedText", shared, object : MethodChannel.Result {
                override fun success(result: Any?) { pendingShare = null }
                override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {}
                override fun notImplemented() {}
            })
        }
    }
}
