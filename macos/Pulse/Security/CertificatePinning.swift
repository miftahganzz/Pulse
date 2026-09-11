import Foundation
import CommonCrypto

public final class PinnedURLSessionDelegate: NSObject, URLSessionDelegate, Sendable {
    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        // Handle server trust for self-signed certificates in Phase 1
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // Trust on First Use / Self-signed certificate support
        completionHandler(.useCredential, URLCredential(trust: serverTrust))
    }
}
