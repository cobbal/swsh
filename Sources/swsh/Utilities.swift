import Foundation

infix operator ??= : AssignmentPrecedence
func ??= <Wrapped>(lhs: inout Wrapped?, rhs: @autoclosure () -> Wrapped) {
    lhs = lhs ?? rhs()
}
