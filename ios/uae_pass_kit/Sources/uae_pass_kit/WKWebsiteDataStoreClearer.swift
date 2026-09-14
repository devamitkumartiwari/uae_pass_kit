import WebKit

/// Clears every website data record from the shared `WKWebsiteDataStore`,
/// as part of [UaePassKitPlugin]'s `signOut` — the WebView-backed
/// equivalent of `UaePassKit.logout()`'s Android cookie clearing.
enum WKWebsiteDataStoreClearer {
  static func clearAll(completion: @escaping () -> Void) {
    let dataStore = WKWebsiteDataStore.default()
    dataStore.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
      dataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: records) {
        completion()
      }
    }
  }
}
