import Flutter
import Testing
import UIKit

@testable import uae_pass_kit

/// Unit tests for the Swift side of uae_pass_kit. They cover the method-call
/// validation and helpers that run without presenting any UI.
@MainActor
struct RunnerTests {

  /// Sends [method] to a fresh plugin and returns what it answered.
  private func call(_ method: String, _ arguments: [String: Any] = [:]) -> Any? {
    let plugin = UaePassKitPlugin()
    var answer: Any?
    plugin.handle(FlutterMethodCall(methodName: method, arguments: arguments)) { answer = $0 }
    return answer
  }

  @Test func unknownMethodIsNotImplemented() {
    #expect(call("getPlatformVersion") as AnyObject === FlutterMethodNotImplemented as AnyObject)
  }

  @Test func isUaePassAppInstalledRequiresScheme() {
    #expect((call("isUaePassAppInstalled") as? FlutterError)?.code == "invalid_argument")
  }

  @Test func isUaePassAppInstalledReturnsBool() {
    #expect(call("isUaePassAppInstalled", ["iosUrlScheme": "uaepassstg"]) is Bool)
  }

  @Test func setUpEnvironmentRequiresBothSchemes() {
    let error = call("setUpEnvironment", ["appCallbackScheme": "myapp"]) as? FlutterError
    #expect(error?.code == "invalid_argument")
  }

  @Test func setUpEnvironmentSucceedsWithBothSchemes() {
    let answer = call(
      "setUpEnvironment", ["appCallbackScheme": "myapp", "uaePassScheme": "uaepassstg"])
    #expect(answer == nil)
  }

  @Test func signInWithoutSetUpIsInvalidArgument() {
    let error = call("signIn", ["authorizeUrl": "https://stg-id.uaepass.ae/idshub/authorize"])
      as? FlutterError
    #expect(error?.code == "invalid_argument")
  }

  @Test func queryValueReadsFirstMatchingParameter() {
    let url = URL(string: "https://example.com/cb?code=abc&state=xyz&code=ignored")!
    #expect(url.queryValue(for: "code") == "abc")
    #expect(url.queryValue(for: "state") == "xyz")
    #expect(url.queryValue(for: "missing") == nil)
  }
}
