import Foundation

/// Shared transport constants for discovery and connection.
public enum FipleService {
    /// Bonjour service type advertised by the Mac companion.
    public static let bonjourType = "_fiple._tcp"
    /// Protocol version negotiated implicitly via the message schema.
    public static let protocolVersion = 1
}

public enum TransportError: Error, Equatable {
    case notConnected
    case connectionFailed(String)
    case decodingFailed
}
