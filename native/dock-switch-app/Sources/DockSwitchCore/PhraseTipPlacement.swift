import Foundation

public enum PhraseTipPlacement {
    public static func frame(size: CGSize, visibleFrame area: CGRect) -> CGRect {
        let width = min(size.width, area.width)
        let height = min(size.height, area.height)
        return CGRect(x: area.midX - width / 2,
                      y: min(area.minY + 24, area.maxY - height), width: width, height: height)
    }
}
