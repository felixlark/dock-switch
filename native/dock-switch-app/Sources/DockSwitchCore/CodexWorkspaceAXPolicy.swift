import Foundation

enum CodexWorkspaceShell {
    static func isPrimaryWebArea(role: String?, url: URL?) -> Bool {
        role == "AXWebArea" && url?.scheme == "app" && url?.host == "-" && url?.path == "/index.html"
    }
}

/// A failed AX read is different from a successfully scanned, absent control.
enum CodexWorkspaceSearchResult<Element> {
    case found(Element)
    case absent
    case unknown
}

struct CodexWorkspaceScanNode<Element> {
    let role: String
    let label: String
    /// nil means the children could not be read. Pruned leaves use an empty array.
    let children: [Element]?
    let subrole: String

    init(role: String, label: String, children: [Element]?, subrole: String = "") {
        self.role = role
        self.label = label
        self.children = children
        self.subrole = subrole
    }
}

enum CodexWorkspaceTreeSearch {
    static func prunesChildren(role: String, label: String) -> Bool {
        ["Conversation", "Latest response", "Navigation", "App navigation"].contains(label) ||
            ["AXStaticText", "AXTextArea", "AXTextField", "AXCheckBox", "AXPopUpButton", "AXList", "AXOutline", "AXTable", "AXComboBox", "AXLink", "AXTabGroup", "AXToolbar"].contains(role) ||
            (role == "AXButton" && !label.isEmpty)
    }

    static func find<Element: Hashable>(
        root: Element,
        read: (Element) -> CodexWorkspaceScanNode<Element>?,
        matching: (String, String) -> Bool
    ) -> CodexWorkspaceSearchResult<Element> {
        findNode(root: root, read: read, matching: { matching($0.role, $0.label) })
    }

    static func findNode<Element: Hashable>(
        root: Element,
        read: (Element) -> CodexWorkspaceScanNode<Element>?,
        matching: (CodexWorkspaceScanNode<Element>) -> Bool
    ) -> CodexWorkspaceSearchResult<Element> {
        var queue = [root]
        var visited = Set<Element>()
        var index = 0
        var incomplete = false
        while index < queue.count {
            let element = queue[index]
            index += 1
            guard visited.insert(element).inserted else { continue }
            guard let node = read(element) else { incomplete = true; continue }
            if matching(node) { return .found(element) }
            guard let children = node.children else { incomplete = true; continue }
            queue += children
        }
        return incomplete ? .unknown : .absent
    }
}

/// Successful and explicitly unsupported subscriptions are terminal until detach;
/// transient AX failures are retried by lifecycle maintenance, without a retry cap.
struct CodexWorkspaceSubscriptions<Element: Hashable> {
    struct Key: Hashable {
        let element: Element
        let notification: String
    }
    enum Outcome: Equatable { case active, unsupported, retryable(Int32) }
    private(set) var outcomes: [Key: Outcome] = [:]

    mutating func ensure(element: Element, notification: String, register: () -> Outcome) {
        let key = Key(element: element, notification: notification)
        switch outcomes[key] {
        case .active?, .unsupported?: return
        default: outcomes[key] = register()
        }
    }

    mutating func remove(where shouldRemove: (Key) -> Bool, unregister: (Key) -> Void) {
        for key in Array(outcomes.keys) where shouldRemove(key) {
            if outcomes[key] == .active { unregister(key) }
            outcomes.removeValue(forKey: key)
        }
    }

    var activeCount: Int { outcomes.values.filter { $0 == .active }.count }
    var unsupportedCount: Int { outcomes.values.filter { $0 == .unsupported }.count }
    var retryableCount: Int {
        outcomes.values.filter { if case .retryable = $0 { return true }; return false }.count
    }
}

/// Public AX exposes wrapper groups that a rendered accessibility tree may flatten.
/// Walk to the nearest group containing workspace controls, never past an unknown
/// state or the app-shell boundary supplied by inspect.
enum CodexWorkspaceHeaderState<Element> {
    case open
    case closed(Element)
    case absent
    case unknown
}

enum CodexWorkspaceHeaderSearch {
    static func nearest<Element: Hashable>(
        startingAt start: Element,
        parent: (Element) -> Element?,
        inspect: (Element) -> CodexWorkspaceHeaderState<Element>
    ) -> CodexWorkspaceHeaderState<Element> {
        var current = start
        var visited = Set<Element>()
        while visited.insert(current).inserted {
            let state = inspect(current)
            switch state {
            case .absent:
                guard let next = parent(current) else { return .unknown }
                current = next
            default: return state
            }
        }
        return .unknown
    }
}
