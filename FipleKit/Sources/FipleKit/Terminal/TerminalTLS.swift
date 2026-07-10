import Foundation
import Network
import CryptoKit

/// TLS parameters for the privileged terminal channel.
///
/// ADR-0002 names the preferred encrypted target as "TLS with a key derived from
/// the pairing code — PAKE or PSK". This uses **TLS 1.2 with an external
/// pre-shared key** (TLS_PSK_WITH_AES_128_GCM_SHA256) derived from the
/// already-established pairing token: both peers prove knowledge of the same
/// secret during the handshake, so the channel is encrypted *and* mutually
/// authenticated (no trust-on-first-use window, no certificate lifecycle).
/// 1.2 rather than 1.3 because Apple's stack fails the 1.3 external-PSK
/// handshake (-9858); see the pinning below. The master password remains a
/// separate second factor checked after the channel is up
/// (see ``TerminalAuthenticator``).
public enum TerminalTLS {
    private static let pskIdentity = "fiple-terminal-v1"
    private static let hkdfInfo = Data("fiple-terminal-psk".utf8)

    /// Derives the 32-byte channel PSK from the pairing token. The token is a
    /// high-entropy bearer secret shared over the (already paired) tile channel;
    /// HKDF domain-separates it from any other use of the token.
    public static func derivePSK(pairingToken: String) -> SymmetricKey {
        let ikm = SymmetricKey(data: Data(pairingToken.utf8))
        return HKDF<SHA256>.deriveKey(inputKeyMaterial: ikm, info: hkdfInfo, outputByteCount: 32)
    }

    /// Server-side parameters (the Mac's terminal listener).
    public static func serverParameters(pairingToken: String) -> NWParameters {
        parameters(psk: derivePSK(pairingToken: pairingToken))
    }

    /// Client-side parameters (the phone).
    public static func clientParameters(pairingToken: String) -> NWParameters {
        parameters(psk: derivePSK(pairingToken: pairingToken))
    }

    private static func parameters(psk: SymmetricKey) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        let pskData = psk.withUnsafeBytes { DispatchData(bytes: $0) }
        let identityData = pskIdentity.data(using: .utf8)!.withUnsafeBytes { DispatchData(bytes: $0) }

        sec_protocol_options_add_pre_shared_key(
            tls.securityProtocolOptions,
            pskData as __DispatchData,
            identityData as __DispatchData
        )
        // External out-of-band PSK is negotiated with a TLS 1.2 PSK ciphersuite
        // (TLS_PSK_WITH_AES_128_GCM_SHA256, 0x00A8). Pin the version to 1.2 so
        // the handshake doesn't fall through to a 1.3 path that ignores the PSK.
        sec_protocol_options_append_tls_ciphersuite(
            tls.securityProtocolOptions,
            tls_ciphersuite_t(rawValue: 0x00A8)!
        )
        sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)

        let params = NWParameters(tls: tls)
        // Terminal I/O is latency-sensitive; disable Nagle so keystrokes flush.
        if let tcp = params.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
            tcp.noDelay = true
        }
        return params
    }
}
