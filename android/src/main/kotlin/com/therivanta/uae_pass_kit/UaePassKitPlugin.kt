package com.therivanta.uae_pass_kit

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.webkit.CookieManager
import android.webkit.WebStorage
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry

/**
 * UaePassKitPlugin
 *
 * Owns every part of the UAE Pass flow that involves the browser/native-app
 * hand-off and the deep-link return, because that hand-off is what the
 * Dart-side `webview_flutter` + `url_launcher` + `app_links` combination
 * proved unreliable for (the flow getting stuck after control bounced out
 * to the UAE Pass app or Chrome). Everything else (token exchange, profile
 * fetch, document upload/poll/download) stays in Dart — see the plugin
 * README.
 *
 * Sign-in and document signing both run in one native [UaePassWebFlowDialog],
 * mirroring iOS's `UaePassWebFlowViewController`: intercept navigation to the
 * redirect/finish URL, and intercept UAE Pass's own `uaepass://` links to hand
 * off to the native app, which returns through this app's fixed
 * `appCallbackScheme://success` / `appCallbackScheme://failure` sentinels
 * (delivered to [onNewIntent]). Sign-in never needs `client_secret`.
 */
class UaePassKitPlugin :
    FlutterPlugin,
    MethodCallHandler,
    ActivityAware,
    PluginRegistry.NewIntentListener {
    private lateinit var channel: MethodChannel
    private lateinit var appContext: Context
    private var activityBinding: ActivityPluginBinding? = null

    private var appCallbackScheme: String? = null
    private var uaePassScheme: String? = null

    /** The web flow currently awaiting a result, if any. */
    private var pendingWebFlow: UaePassWebFlowDialog? = null

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addOnNewIntentListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        onDetachedFromActivity()
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivity() {
        activityBinding?.removeOnNewIntentListener(this)
        activityBinding = null
        pendingWebFlow?.abort("The app was closed before UAE Pass finished")
    }

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        appContext = flutterPluginBinding.applicationContext
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "uae_pass_kit")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(
        call: MethodCall,
        result: Result,
    ) {
        when (call.method) {
            "isUaePassAppInstalled" -> {
                val packageId = call.argument<String>("androidPackageId")
                if (packageId.isNullOrEmpty()) {
                    result.error("invalid_argument", "androidPackageId is required", null)
                    return
                }
                result.success(isPackageInstalled(packageId))
            }
            "setUpEnvironment" -> {
                val appCallbackScheme = call.argument<String>("appCallbackScheme")
                val uaePassScheme = call.argument<String>("uaePassScheme")
                if (appCallbackScheme.isNullOrEmpty() || uaePassScheme.isNullOrEmpty()) {
                    result.error(
                        "invalid_argument",
                        "appCallbackScheme and uaePassScheme are required",
                        null,
                    )
                    return
                }
                this.appCallbackScheme = appCallbackScheme
                this.uaePassScheme = uaePassScheme
                result.success(null)
            }
            "signIn" -> signIn(call, result)
            "openSigningUrl" -> openSigningUrl(call, result)
            "signOut" -> {
                CookieManager.getInstance().removeAllCookies(null)
                CookieManager.getInstance().flush()
                WebStorage.getInstance().deleteAllData()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    // ---- signIn ----

    private fun signIn(
        call: MethodCall,
        result: Result,
    ) {
        val authorizeUrl = call.argument<String>("authorizeUrl")?.let(Uri::parse)
        val redirectUri = authorizeUrl?.getQueryParameter("redirect_uri")
        val state = authorizeUrl?.getQueryParameter("state")
        if (authorizeUrl == null || redirectUri == null) {
            result.error(
                "invalid_argument",
                "authorizeUrl is required and setUpEnvironment must be called first",
                null,
            )
            return
        }

        presentWebFlow(
            initialUrl = authorizeUrl.toString(),
            isFinished = { it.toString().startsWith(redirectUri) },
            result = result,
        ) { finishedUrl ->
            val authError = finishedUrl.getQueryParameter("error")
            when {
                authError != null ->
                    result.error(
                        "ERROR",
                        finishedUrl.getQueryParameter("error_description") ?: authError,
                        null,
                    )
                finishedUrl.getQueryParameter("state") != state ->
                    result.error("ERROR", "UAE Pass returned a mismatched state", null)
                else -> result.success(finishedUrl.getQueryParameter("code"))
            }
        }
    }

    // ---- openSigningUrl ----

    private fun openSigningUrl(
        call: MethodCall,
        result: Result,
    ) {
        val url = call.argument<String>("url")
        if (url == null) {
            result.error("invalid_argument", "url is required", null)
            return
        }
        val finishScheme = call.argument<String>("finishScheme")
        val finishHost = call.argument<String>("finishHost")
        val finishPath = call.argument<String>("finishPath")

        presentWebFlow(
            initialUrl = url,
            isFinished = { uri ->
                uri.getQueryParameter("status") != null ||
                    (
                        finishScheme != null &&
                            uri.scheme == finishScheme &&
                            uri.host == finishHost &&
                            (uri.path ?: "") == (finishPath ?: "")
                    )
            },
            result = result,
        ) { finishedUrl -> result.success(finishedUrl.toString()) }
    }

    // ---- Shared web-flow presentation ----

    /**
     * Shows a [UaePassWebFlowDialog]. A cancellation completes [result] with
     * `null` and an error with `"ERROR"`; a finished URL is handed to
     * [onFinishedUrl] to complete [result].
     */
    private fun presentWebFlow(
        initialUrl: String,
        isFinished: (Uri) -> Boolean,
        result: Result,
        onFinishedUrl: (Uri) -> Unit,
    ) {
        val activity = activityBinding?.activity
        val appCallbackScheme = this.appCallbackScheme
        val uaePassScheme = this.uaePassScheme
        if (activity == null || appCallbackScheme == null || uaePassScheme == null) {
            result.error(
                "invalid_state",
                "UAE Pass needs a foreground activity, and setUpEnvironment must be called first",
                null,
            )
            return
        }
        if (pendingWebFlow != null) {
            result.error("ERROR", "A UAE Pass flow is already in progress", null)
            return
        }

        pendingWebFlow =
            UaePassWebFlowDialog(
                activity = activity,
                initialUrl = initialUrl,
                appCallbackScheme = appCallbackScheme,
                uaePassScheme = uaePassScheme,
                isFinished = isFinished,
            ) { finishedUrl, error ->
                pendingWebFlow = null
                when {
                    error != null -> result.error("ERROR", error, null)
                    finishedUrl == null -> result.success(null) // cancelled
                    else -> onFinishedUrl(finishedUrl)
                }
            }.also { it.show() }
    }

    // ---- App-to-app return ----

    /**
     * Catches the return from the native UAE Pass app via this app's own
     * fixed `appCallbackScheme://success` / `appCallbackScheme://failure`
     * sentinel URLs, and resumes whichever web flow is currently pending.
     * Anything else is left to the host app.
     */
    override fun onNewIntent(intent: Intent): Boolean {
        val data = intent.data ?: return false
        val flow = pendingWebFlow ?: return false
        if (!data.scheme.equals(appCallbackScheme, ignoreCase = true)) return false
        when (data.host?.lowercase()) {
            "success" -> flow.onReturnFromUaePassApp(success = true)
            "failure" -> flow.onReturnFromUaePassApp(success = false)
            else -> return false
        }
        return true
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
}
