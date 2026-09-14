import Foundation

extension URL {
  /// The value of the first query parameter named [name], if present.
  func queryValue(for name: String) -> String? {
    URLComponents(url: self, resolvingAgainstBaseURL: false)?
      .queryItems?
      .first(where: { $0.name == name })?
      .value
  }
}
