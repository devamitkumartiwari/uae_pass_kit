package com.therivanta.uae_pass_kit

import android.annotation.SuppressLint
import android.app.Activity
import android.app.Dialog
import android.content.ActivityNotFoundException
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Color
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.WindowManager
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import android.widget.ProgressBar
import android.window.OnBackInvokedCallback
import android.window.OnBackInvokedDispatcher

/**
 * A full-screen `WebView` dialog that drives any UAE Pass flow built on the
 * documented app-to-app interception mechanics — shared by both the login
 * flow and the e-signature flow, the Android counterpart of iOS's
 * `UaePassWebFlowViewController`.
 *
 * This dialog only orchestrates navigation and the native-app hand-off; it
 * has no opinion on what a "finished" URL means beyond the [isFinished]
 * predicate it's given. [onFinished] is called exactly once, with the final
 * URL (or `null` if the user cancelled) and an optional error message.
 */
internal class UaePassWebFlowDialog(
    private val activity: Activity,
    private val initialUrl: String,
    private val appCallbackScheme: String,
    private val uaePassScheme: String,
    private val isFinished: (Uri) -> Boolean,
    private val onFinished: (finishedUrl: Uri?, error: String?) -> Unit,
) : Dialog(activity, android.R.style.Theme_DeviceDefault_Light_NoActionBar) {
    private lateinit var webView: WebView
    private lateinit var progressBar: ProgressBar
    private var hasFinished = false
    private var backCallback: OnBackInvokedCallback? = null

    /**
     * The original `successurl` UAE Pass sent in its `uaepass://` hand-off
     * request, captured before [rewriteForNativeAppHandoff] replaces it with
     * this app's fixed sentinel URL — reloaded by [onReturnFromUaePassApp]
     * once the native UAE Pass app hands control back.
     */
    private var cachedSuccessUrl: String? = null

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setCancelable(true)
        setOnCancelListener { finish(null, null) }

        val root = FrameLayout(context).apply { setBackgroundColor(Color.WHITE) }
        webView =
            WebView(context).apply {
                settings.javaScriptEnabled = true
                settings.domStorageEnabled = true
                settings.setSupportMultipleWindows(false)
                webViewClient = Client()
            }
        progressBar = ProgressBar(context).apply { isIndeterminate = true }
        root.addView(webView, FrameLayout.LayoutParams(MATCH, MATCH))
        root.addView(progressBar, FrameLayout.LayoutParams(WRAP, WRAP, Gravity.CENTER))
        setContentView(root)

        window?.apply {
            setLayout(MATCH, MATCH)
            setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                // White background behind the bars, so request dark bar icons.
                val light =
                    WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS or
                        WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS
                insetsController?.setSystemBarsAppearance(light, light)
            }
        }
        applySafeAreaPadding(root)

        webView.loadUrl(initialUrl)
        webView.requestFocus()
    }

    override fun onStart() {
        super.onStart()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val callback = OnBackInvokedCallback { handleBack() }
            onBackInvokedDispatcher.registerOnBackInvokedCallback(
                OnBackInvokedDispatcher.PRIORITY_DEFAULT,
                callback,
            )
            backCallback = callback
        }
    }

    override fun onStop() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            backCallback?.let { onBackInvokedDispatcher.unregisterOnBackInvokedCallback(it) }
            backCallback = null
        }
        super.onStop()
    }

    @Deprecated("Used below Android 13; newer versions use OnBackInvokedCallback.")
    @Suppress("DEPRECATION")
    override fun onBackPressed() {
        handleBack()
    }

    override fun dismiss() {
        if (::webView.isInitialized) {
            webView.stopLoading()
            webView.destroy()
        }
        super.dismiss()
    }

    /**
     * Called by [UaePassKitPlugin] once the native UAE Pass app opens this
     * app's fixed `appCallbackScheme://success` / `appCallbackScheme://failure`
     * sentinel: reloads the cached `successurl` to resume the flow, or
     * finishes as cancelled.
     */
    fun onReturnFromUaePassApp(success: Boolean) {
        val successUrl = cachedSuccessUrl
        when {
            !success -> finish(null, null)
            successUrl != null -> webView.loadUrl(successUrl)
            else -> webView.reload()
        }
    }

    /** Ends the flow from outside, e.g. when the host activity goes away. */
    fun abort(error: String) {
        finish(null, error)
    }

    private fun handleBack() {
        if (webView.canGoBack()) webView.goBack() else finish(null, null)
    }

    private fun finish(finishedUrl: Uri?, error: String?) {
        if (hasFinished) return
        hasFinished = true
        if (isShowing) dismiss()
        onFinished(finishedUrl, error)
    }

    /**
     * Pads the content to the system bars, display cutout and keyboard so the
     * page stays inside the safe area, both on edge-to-edge windows (enforced
     * from targetSdk 35) and on older versions.
     */
    private fun applySafeAreaPadding(root: View) {
        root.setOnApplyWindowInsetsListener { view, insets ->
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val safe =
                    insets.getInsets(
                        WindowInsets.Type.systemBars() or
                            WindowInsets.Type.displayCutout() or
                            WindowInsets.Type.ime(),
                    )
                view.setPadding(safe.left, safe.top, safe.right, safe.bottom)
            } else {
                @Suppress("DEPRECATION")
                view.setPadding(
                    insets.systemWindowInsetLeft,
                    insets.systemWindowInsetTop,
                    insets.systemWindowInsetRight,
                    insets.systemWindowInsetBottom,
                )
            }
            insets
        }
        root.requestApplyInsets()
    }

    /** Returns true when [uri] was consumed and must not be loaded. */
    private fun handleNavigation(uri: Uri): Boolean {
        if (isFinished(uri)) {
            finish(uri, null)
            return true
        }

        // UAE Pass's pages always link to `uaepass://`, whatever the
        // environment; retarget it at the
        // environment's own app (e.g. `uaepassstg://` on staging).
        if (uri.scheme == "uaepass" || uri.scheme == uaePassScheme) {
            try {
                activity.startActivity(Intent(Intent.ACTION_VIEW, rewriteForNativeAppHandoff(uri)))
            } catch (e: ActivityNotFoundException) {
                finish(null, "The UAE Pass app is not available")
            }
            return true
        }

        return false
    }

    /**
     * Rewrites the hand-off so the native UAE Pass app returns to this app's
     * fixed `appCallbackScheme://success` / `appCallbackScheme://failure`
     * sentinel URLs, first caching the original `successurl` into
     * [cachedSuccessUrl].
     *
     * The original query is replaced by unencoded success/failure URLs only. In particular
     * `closeondone=true` (meant for iOS) must not be forwarded — with it the
     * Android UAE Pass app closes itself without opening the success URL,
     * leaving the flow stuck.
     */
    private fun rewriteForNativeAppHandoff(uri: Uri): Uri {
        cachedSuccessUrl =
            uri.queryParameterNames
                .firstOrNull { it.equals("successurl", ignoreCase = true) }
                ?.let { uri.getQueryParameter(it) }
        // Schemes are case-insensitive, but Android intent filters expect lowercase.
        val callback = appCallbackScheme.lowercase()
        return Uri.parse(
            "$uaePassScheme://" + uri.encodedAuthority.orEmpty() + uri.encodedPath.orEmpty() +
                "?successurl=$callback://success" +
                "&failureurl=$callback://failure",
        )
    }

    private inner class Client : WebViewClient() {
        override fun shouldOverrideUrlLoading(
            view: WebView,
            request: WebResourceRequest,
        ): Boolean = handleNavigation(request.url)

        override fun onPageStarted(
            view: WebView,
            url: String,
            favicon: Bitmap?,
        ) {
            progressBar.visibility = View.VISIBLE
        }

        override fun onPageFinished(
            view: WebView,
            url: String,
        ) {
            progressBar.visibility = View.GONE
        }

        override fun onReceivedError(
            view: WebView,
            request: WebResourceRequest,
            error: WebResourceError,
        ) {
            if (request.isForMainFrame) finish(null, error.description?.toString())
        }
    }

    private companion object {
        const val MATCH = ViewGroup.LayoutParams.MATCH_PARENT
        const val WRAP = ViewGroup.LayoutParams.WRAP_CONTENT
    }
}
