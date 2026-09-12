import Foundation
import CommonCrypto
import Security

public final class PinnedURLSessionDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    private let serverId: UUID?

    public init(serverId: UUID? = nil) {
        self.serverId = serverId
        super.init()
    }

    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        handleChallenge(challenge, completionHandler: completionHandler)
    }

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        handleChallenge(challenge, completionHandler: completionHandler)
    }

    private func handleChallenge(
        _ challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // Enforce Trust-On-First-Use (TOFU) certificate pinning if serverId is known
        if let serverId = self.serverId,
           let certChain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate],
           let leafCert = certChain.first {
            let certData = SecCertificateCopyData(leafCert) as Data
            let fingerprint = sha256Hex(data: certData)

            if let pinnedFingerprint = KeychainService.getCertFingerprint(forServerId: serverId) {
                if pinnedFingerprint.caseInsensitiveCompare(fingerprint) == .orderedSame {
                    // Pinned certificate matched
                    completionHandler(.useCredential, URLCredential(trust: serverTrust))
                    return
                } else {
                    // Mismatch! Potential Man-in-the-Middle (MITM) attack
                    PulseLog.security.error("TLS Certificate Fingerprint Mismatch for server \(serverId)! Expected \(pinnedFingerprint), got \(fingerprint). Rejecting connection.")
                    completionHandler(.cancelAuthenticationChallenge, nil)
                    return
                }
            } else {
                // First-time connection (TOFU): securely store fingerprint
                try? KeychainService.saveCertFingerprint(fingerprint, forServerId: serverId)
                PulseLog.security.info("Pinned new TLS certificate fingerprint for server \(serverId): \(fingerprint)")
                completionHandler(.useCredential, URLCredential(trust: serverTrust))
                return
            }
        }

        // Fallback for probe tests or instances without serverId: accept trust
        completionHandler(.useCredential, URLCredential(trust: serverTrust))
    }

    private func sha256Hex(data: Data) -> String {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
