package com.uaepasskit.uae_pass_kit

import android.content.Context
import android.content.pm.PackageManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * UaePassKitPlugin
 *
 * The only native responsibility of this plugin: checking whether the
 * native UAE Pass app is installed, via Android's package-visibility APIs.
 * Every other capability (the OAuth flow, all API calls) is implemented in
 * pure Dart — see the plugin README for why.
 */
class UaePassKitPlugin :
    FlutterPlugin,
    MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var appContext: Context

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        appContext = flutterPluginBinding.applicationContext
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "uae_pass_kit")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(
        call: MethodCall,
        result: Result
    ) {
        when (call.method) {
            "isUaePassAppInstalled" -> {
                val packageId = call.argument<String>("androidPackageId")
                if (packageId.isNullOrEmpty()) {
                    result.error(
                        "invalid_argument",
                        "androidPackageId is required",
                        null
                    )
                    return
                }
                result.success(isPackageInstalled(packageId))
            }
            else -> result.notImplemented()
        }
    }

    /**
     * Requires the calling app to declare [packageId] under a `<queries>`
     * element in its AndroidManifest.xml (Android 11+ package-visibility
     * requirement) — this plugin ships that declaration for all UAE Pass
     * package variants via its own manifest, which merges into the host
     * app's manifest automatically.
     */
    private fun isPackageInstalled(packageId: String): Boolean {
        return try {
            appContext.packageManager.getPackageInfo(packageId, 0)
            true
        } catch (e: PackageManager.NameNotFoundException) {
            false
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }
}
