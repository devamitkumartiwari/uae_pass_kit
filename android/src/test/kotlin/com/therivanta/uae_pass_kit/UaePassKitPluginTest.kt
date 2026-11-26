package com.therivanta.uae_pass_kit

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/*
 * Unit tests for the argument validation in UaePassKitPlugin's method-call
 * handler. These paths never touch the Android framework, so they run on the
 * plain JVM.
 *
 * Run them with `./gradlew :uae_pass_kit:testDebugUnitTest` from
 * `example/android/`, after building the example app once.
 */
internal class UaePassKitPluginTest {
    private class RecordingResult : MethodChannel.Result {
        var successValue: Any? = null
        var errorCode: String? = null
        var notImplemented = false

        override fun success(result: Any?) {
            successValue = result
        }

        override fun error(
            errorCode: String,
            errorMessage: String?,
            errorDetails: Any?,
        ) {
            this.errorCode = errorCode
        }

        override fun notImplemented() {
            notImplemented = true
        }
    }

    private fun call(
        method: String,
        arguments: Map<String, Any?> = emptyMap(),
    ): RecordingResult {
        val result = RecordingResult()
        UaePassKitPlugin().onMethodCall(MethodCall(method, arguments), result)
        return result
    }

    @Test
    fun unknownMethod_isNotImplemented() {
        assertTrue(call("getPlatformVersion").notImplemented)
    }

    @Test
    fun isUaePassAppInstalled_withoutPackageId_isInvalidArgument() {
        assertEquals("invalid_argument", call("isUaePassAppInstalled").errorCode)
        assertEquals(
            "invalid_argument",
            call("isUaePassAppInstalled", mapOf("androidPackageId" to "")).errorCode,
        )
    }

    @Test
    fun setUpEnvironment_requiresBothSchemes() {
        assertEquals(
            "invalid_argument",
            call("setUpEnvironment", mapOf("appCallbackScheme" to "myapp")).errorCode,
        )
        assertEquals(
            "invalid_argument",
            call("setUpEnvironment", mapOf("uaePassScheme" to "uaepassstg")).errorCode,
        )
    }

    @Test
    fun setUpEnvironment_withBothSchemes_succeeds() {
        val result =
            call(
                "setUpEnvironment",
                mapOf("appCallbackScheme" to "myapp", "uaePassScheme" to "uaepassstg"),
            )
        assertEquals(null, result.errorCode)
        assertEquals(null, result.successValue)
    }

    @Test
    fun openSigningUrl_withoutUrl_isInvalidArgument() {
        assertEquals("invalid_argument", call("openSigningUrl").errorCode)
    }
}
