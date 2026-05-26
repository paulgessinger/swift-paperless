import Foundation

/// Fetches and validates a favicon from a given URL
///
/// This function:
/// 1. Requests the given URL
/// 2. Checks for an HTML response
/// 3. Parses for `<link rel="icon" href="...">` element
/// 4. Verifies the icon exists with a HEAD request
///
/// - Parameter url: The URL to check for a favicon
/// - Returns: The validated favicon URL, or nil if not found or validation fails
public func fetchFavicon(from url: URL) async -> URL? {
  let session = URLSession.shared

  // Step 1: Request the URL
  let (data, response): (Data, URLResponse)
  do {
    (data, response) = try await session.data(from: url)
  } catch {
    return nil
  }

  // Step 2: Check for HTML response
  guard let httpResponse = response as? HTTPURLResponse,
    httpResponse.statusCode == 200,
    let mimeType = httpResponse.mimeType,
    mimeType.lowercased().contains("html")
  else {
    return nil
  }

  // Step 3: Parse HTML for favicon link
  guard let html = String(data: data, encoding: .utf8) else {
    return nil
  }

  guard let iconHref = extractIconHref(from: html) else {
    return nil
  }

  // Resolve relative URL
  guard let iconURL = URL(string: iconHref, relativeTo: url)?.absoluteURL else {
    return nil
  }

  // Step 4: Verify icon exists with HEAD request
  var request = URLRequest(url: iconURL)
  request.httpMethod = "HEAD"

  let (_, headResponse): (Data, URLResponse)
  do {
    (_, headResponse) = try await session.data(for: request)
  } catch {
    return nil
  }

  guard let headHttpResponse = headResponse as? HTTPURLResponse,
    (200..<300).contains(headHttpResponse.statusCode)
  else {
    return nil
  }

  return iconURL
}

/// Extracts the href value from a `<link rel="icon" href="...">` element
///
/// - Parameter html: The HTML string to parse
/// - Returns: The href value if found, otherwise nil
private func extractIconHref(from html: String) -> String? {
  // Look for <link rel="icon" href="...">
  // Use \s to match word boundary before href to avoid matching data-href, base-href, etc.
  let pattern = /<link[^>]*rel\s*=\s*["']icon["'][^>]*\shref\s*=\s*["'](.*?)["']/
  let alternatePattern = /<link[^>]*\shref\s*=\s*["'](.*?)["'][^>]*rel\s*=\s*["']icon["']/

  // Try first pattern (rel before href)
  if let match = html.firstMatch(of: pattern) {
    return String(match.1)
  }

  // Try alternate pattern (href before rel)
  if let match = html.firstMatch(of: alternatePattern) {
    return String(match.1)
  }

  return nil
}
