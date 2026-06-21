import Foundation
import Carbon  // IsSecureEventInputEnabled

/// Secure Input silently swallows synthesized key events. Behind a protocol so
/// the engine's blocked-path is testable without toggling system state.
public protocol SecureInputChecking {
    func isActive() -> Bool
}

public struct SystemSecureInput: SecureInputChecking {
    public init() {}
    public func isActive() -> Bool { IsSecureEventInputEnabled() }
}
