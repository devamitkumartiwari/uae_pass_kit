package com.therivanta.uae_pass_kit

import ae.sdg.libraryuaepass.UAEPassAccessCodeCallback
import ae.sdg.libraryuaepass.UAEPassController.getAccessCode
import ae.sdg.libraryuaepass.UAEPassController.resume
import ae.sdg.libraryuaepass.business.Environment
import ae.sdg.libraryuaepass.business.Language
import ae.sdg.libraryuaepass.business.authentication.model.UAEPassAccessTokenRequestModel
import android.app.Activity
import android.app.Dialog
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
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
 * Sign-in is delegated entirely to UAE Pass's official native Android SDK
 * (the vendored `libraryuaepass.aar`), which owns the app-switch and the
 * `onNewIntent` resume internally. Document signing has no such official
 * primitive compatible with this plugin's HTTP-based signing pipeline (see
 * [UaePassDocumentSigningRequestModel] in the AAR, which wants a local
 * `File` and its own token flow), so `openSigningUrl` instead drives a
 * small native `WebView` dialog with the exact same app-switch/deep-link
 * mechanics the AAR uses internally.
 */
class UaePassKitPlugin :
    FlutterPlugin,
    MethodCallHandler,
    ActivityAware,
    PluginRegistry.NewIntentListener {
    private lateinit var channel: MethodChannel
    private lateinit var appContext: Context
    private var activity: Activity? = null

    private var clientId: String? = null
    private var clientSecret: String? = null
    private var redirectUrl: String? = null
    private var environment: Environment = Environment.STAGING
    private var appCallbackScheme: String? = null
    private var uaePassScheme: String? = null
    private var scope: String? = null
    private var language: String = "en"

    private enum class Flow { NONE, SIGN_IN, SIGNING }

    private var currentFlow = Flow.NONE
    private var signingDialog: Dialog? = null
    private var signingWebView: WebView? = null
    private var signingResult: Result? = null
    private var signingFinishMatcher: ((Uri) -> Boolean)? = null

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addOnNewIntentListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addOnNewIntentListener(this)
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        appContext = flutterPluginBinding.applicationContext
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "uae_pass_kit")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
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
                clientId = call.argument<String>("clientId")
                clientSecret = call.argument<String>("clientSecret")
                redirectUrl = call.argument<String>("redirectUri")
                environment =
                    if (call.argument<Boolean>("isProduction") == true) {
                        Environment.PRODUCTION
                    } else {
                        Environment.STAGING
                    }
                appCallbackScheme = call.argument<String>("appCallbackScheme")
                uaePassScheme = call.argument<String>("uaePassScheme")
                scope = call.argument<String>("scope")
                language = call.argument<String>("language") ?: "en"
                result.success(null)
            }
            "signIn" -> signIn(call, result)
            "openSigningUrl" -> openSigningUrl(call, result)
            "signOut" -> {
                CookieManager.getInstance().removeAllCookies(null)
                CookieManager.getInstance().flush()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    // ---- Sign-in: fully owned by the official AAR ----

    private fun signIn(call: MethodCall, result: Result) {
        val activity = this.activity
        val clientId = this.clientId
        val clientSecret = this.clientSecret
        val redirectUrl = this.redirectUrl
        val appCallbackScheme = this.appCallbackScheme
        val scope = this.scope
        val state = call.argument<String>("state")
        if (activity == null || clientId == null || clientSecret == null ||
            redirectUrl == null || appCallbackScheme == null || scope == null || state == null
        ) {
            result.error(
                "invalid_state",
                "setUpEnvironment must be called with a valid config before signIn",
                null,
            )
            return
        }

        val acrValues =
            if (isPackageInstalled(uaePassPackageIdFor(environment))) {
                ACR_VALUES_MOBILE
            } else {
                ACR_VALUES_WEB
            }
        val requestModel =
            UAEPassAccessTokenRequestModel(
                environment,
                clientId,
                clientSecret,
                appCallbackScheme,
                "failure",
                "success",
                redirectUrl,
                scope,
                RESPONSE_TYPE,
                acrValues,
                state,
                if (language == "ar") Language.AR else Language.EN,
            )

        currentFlow = Flow.SIGN_IN
        getAccessCode(
            activity,
            requestModel,
            object : UAEPassAccessCodeCallback {
                override fun getAccessCode(accessCode: String?, error: String?) {
                    currentFlow = Flow.NONE
                    if (error != null) {
                        result.error("ERROR", error, null)
                    } else {
                        result.success(accessCode)
                    }
                }
            },
        )
    }

    override fun onNewIntent(intent: Intent): Boolean {
        val data = intent.data ?: return false
        if (data.scheme != appCallbackScheme) return false

        return when (currentFlow) {
            Flow.SIGN_IN -> {
                resume(intent.dataString)
                true
            }
            Flow.SIGNING -> {
                val wrapped = data.getQueryParameter("url")
                if (wrapped != null) {
                    activity?.runOnUiThread { signingWebView?.loadUrl(wrapped) }
                }
                true
            }
            Flow.NONE -> false
        }
    }

    // ---- Document signing: a native WebView dialog with the same
    // app-switch/deep-link mechanics the AAR uses internally for sign-in ----

    private fun openSigningUrl(call: MethodCall, result: Result) {
        val activity = this.activity
        val url = call.argument<String>("url")
        val finishScheme = call.argument<String>("finishScheme")
        val finishHost = call.argument<String>("finishHost")
        val finishPath = call.argument<String>("finishPath")
        if (activity == null || url == null) {
            result.error("invalid_argument", "url is required", null)
            return
        }

        val matcher: (Uri) -> Boolean = { uri ->
            (finishScheme != null &&
                uri.scheme == finishScheme &&
                uri.host == finishHost &&
                (uri.path ?: "") == (finishPath ?: "")) ||
                uri.getQueryParameter("status") != null
        }

        currentFlow = Flow.SIGNING
        signingResult = result
        signingFinishMatcher = matcher

        val webView =
            WebView(activity).apply {
                settings.javaScriptEnabled = true
                layoutParams =
                    ViewGroup.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        ViewGroup.LayoutParams.MATCH_PARENT,
                    )
                webViewClient =
                    object : WebViewClient() {
                        override fun shouldOverrideUrlLoading(
                            view: WebView,
                            request: WebResourceRequest,
                        ): Boolean = handleSigningNavigation(request.url)
                    }
                loadUrl(url)
            }
        signingWebView = webView

        val dialog =
            Dialog(activity, android.R.style.Theme_DeviceDefault_NoActionBar_Fullscreen).apply {
                setContentView(webView)
                setOnCancelListener { finishSigning(null, "Signing cancelled by user") }
                setCancelable(true)
            }
        signingDialog = dialog
        dialog.show()
    }

    private fun handleSigningNavigation(uri: Uri): Boolean {
        val matcher = signingFinishMatcher ?: return false

        if (matcher(uri)) {
            finishSigning(uri.toString(), null)
            return true
        }

        if (uri.scheme == uaePassScheme) {
            val rewritten = rewriteForNativeAppHandoff(uri)
            try {
                activity?.startActivity(Intent(Intent.ACTION_VIEW, rewritten))
            } catch (e: Exception) {
                finishSigning(null, "Unable to open UAE Pass app: ${e.message}")
            }
            return true
        }

        return false
    }

    /**
     * Rewrites `successURL`/`failureURL` so the native UAE Pass app hands
     * control back to this app's [appCallbackScheme] instead of its own
     * default — the exact rewrite both official SDKs perform before
     * launching the native app, ported from this plugin's own Dart
     * `UaePassRedirectInterceptor.rewriteForNativeAppHandoff`.
     */
    private fun rewriteForNativeAppHandoff(uri: Uri): Uri {
        val builder = uri.buildUpon().clearQuery()
        for (name in uri.queryParameterNames) {
            val value = uri.getQueryParameter(name) ?: continue
            val rewritten =
                when (name) {
                    "successURL", "successUrl", "failureURL", "failureUrl" ->
                        appCallbackUrl(value)
                    else -> value
                }
            builder.appendQueryParameter(name, rewritten)
        }
        return builder.build()
    }

    private fun appCallbackUrl(originalUrl: String): String {
        return Uri.Builder()
            .scheme(appCallbackScheme)
            .encodedAuthority("")
            .path("/resume_authn")
            .appendQueryParameter("url", originalUrl)
            .build()
            .toString()
    }

    private fun finishSigning(finalUrl: String?, error: String?) {
        if (currentFlow != Flow.SIGNING) return
        currentFlow = Flow.NONE
        activity?.runOnUiThread {
            signingDialog?.setOnCancelListener(null)
            signingDialog?.dismiss()
            signingDialog = null
            signingWebView = null
            val pendingResult = signingResult
            signingResult = null
            signingFinishMatcher = null
            if (pendingResult == null) return@runOnUiThread
            if (error != null) {
                pendingResult.error("ERROR", error, null)
            } else {
                pendingResult.success(finalUrl)
            }
        }
    }

    private fun uaePassPackageIdFor(environment: Environment): String =
        when (environment) {
            is Environment.PRODUCTION -> UAE_PASS_PACKAGE_ID
            else -> UAE_PASS_STG_PACKAGE_ID
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

    private companion object {
        const val UAE_PASS_PACKAGE_ID = "ae.uaepass.mainapp"
        const val UAE_PASS_STG_PACKAGE_ID = "ae.uaepass.mainapp.stg"
        const val RESPONSE_TYPE = "code"
        const val ACR_VALUES_MOBILE = "urn:digitalid:authentication:flow:mobileondevice"
        const val ACR_VALUES_WEB = "urn:safelayer:tws:policies:authentication:level:low"
    }
}
