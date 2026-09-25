import SwiftUI
import UIKit

/// Swipe right on a message to reply. A UIKit pan that only begins on a clearly rightward,
/// horizontal movement: any vertical drag fails it at once and the thread scrolls as usual.
/// (A SwiftUI DragGesture on the rows competed with the scroll view, most visibly on the large
/// session cards.)
struct ReplySwipeGesture: UIGestureRecognizerRepresentable {
    /// Horizontal distance from the start, in points.
    var onChanged: (CGFloat) -> Void
    var onEnded: () -> Void

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        return pan
    }

    func handleUIGestureRecognizerAction(_ pan: UIPanGestureRecognizer, context: Context) {
        switch pan.state {
        case .began, .changed: onChanged(max(0, pan.translation(in: pan.view).x))
        case .ended, .cancelled, .failed: onEnded()
        default: break
        }
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
            guard let pan = gesture as? UIPanGestureRecognizer else { return false }
            // From the screen's left edge, it's the system's swipe back, not a reply.
            if let window = pan.view?.window, pan.location(in: window).x < 28 { return false }
            let v = pan.velocity(in: pan.view)
            return v.x > 0 && abs(v.x) > abs(v.y) * 1.5
        }

        // Buttons inside the message (session times, play) keep working; never alongside the
        // scroll view or the navigation's swipe back.
        func gestureRecognizer(_ gesture: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            !(other.view is UIScrollView) && !isSwipeBack(other, from: gesture.view)
        }

        // iOS 26 goes back with a swipe anywhere on the screen: on a message, the reply swipe wins
        // and the swipe back waits for it to fail.
        func gestureRecognizer(_ gesture: UIGestureRecognizer,
                               shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            isSwipeBack(other, from: gesture.view)
        }

        private func isSwipeBack(_ other: UIGestureRecognizer, from view: UIView?) -> Bool {
            var responder: UIResponder? = view
            while let r = responder {
                if let nav = (r as? UIViewController)?.navigationController {
                    return other === nav.interactiveContentPopGestureRecognizer
                }
                responder = r.next
            }
            return false
        }
    }
}
