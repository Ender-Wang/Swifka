extension Optional: @retroactive Comparable where Wrapped: Comparable {
    public static func < (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case let (l?, r?): l < r
        case (nil, _?): true
        default: false
        }
    }
}
