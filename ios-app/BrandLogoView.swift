import SwiftUI

struct BrandLogoView: View {
    let containerSize: CGSize

    var body: some View {
        RideShiftLogoView()
            .frame(width: Self.logoSize(for: containerSize), height: Self.logoSize(for: containerSize))
    }

    static func logoSize(for size: CGSize) -> CGFloat {
        min(max(min(size.width, size.height) * 0.33, 110), 180)
    }
}
