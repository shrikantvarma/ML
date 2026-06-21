import Foundation

/// Why a switch was blocked. Engine-specific reasons live here so the result
/// type stays general across the future emulated-workspace engine (plan KTD-3).
public enum BlockReason: Equatable {
    case secureInput
    case shortcutDisabled
}

/// Generalized switch outcome — the UI branches on this shape, not on
/// native-Control+N internals, so a second engine drops in with minimal change.
public enum SwitchResult: Equatable {
    case switched(latencyMs: Int)
    case driftDetected            // bound UUID absent from the ordered list
    case notKeyable(index: Int)   // index > 9 → no single Ctrl+number
    case blocked(BlockReason)
    case verificationFailed       // posted but did not land within the timeout
}

/// The single switching boundary (plan R9). All UI/model depend only on this.
public protocol SwitchEngine {
    func `switch`(toSpaceUUID uuid: String) async -> SwitchResult
}
