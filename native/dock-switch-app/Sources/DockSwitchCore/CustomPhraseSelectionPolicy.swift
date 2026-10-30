import ApplicationServices

public enum CustomPhraseSelectionPolicy {
    /// An absent optional subrole is normal for text views. Transport, trust and
    /// malformed-value failures must not be mistaken for a nonsecure field.
    public static func mayRead(subroleStatus: AXError, subrole: String?) -> Bool {
        switch subroleStatus {
        case .attributeUnsupported, .noValue: return true
        case .success: return subrole != nil && subrole != kAXSecureTextFieldSubrole as String
        default: return false
        }
    }
}
