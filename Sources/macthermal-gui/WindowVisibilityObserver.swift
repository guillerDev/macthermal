import AppKit
import SwiftUI

/// Reports the real AppKit window state. SwiftUI can keep a closed Window
/// scene mounted, so onAppear/onDisappear alone do not track visibility.
@MainActor
struct WindowVisibilityObserver: NSViewRepresentable {
    let onChange: @MainActor (Bool) -> Void

    func makeNSView(context: Context) -> WindowVisibilityTrackingView {
        WindowVisibilityTrackingView(onChange: onChange)
    }

    func updateNSView(_ nsView: WindowVisibilityTrackingView, context: Context) {
        nsView.onChange = onChange
        nsView.reportVisibility()
    }

    static func dismantleNSView(_ nsView: WindowVisibilityTrackingView, coordinator: ()) {
        nsView.stopObserving()
    }
}

@MainActor
final class WindowVisibilityTrackingView: NSView {
    var onChange: @MainActor (Bool) -> Void

    private weak var trackedWindow: NSWindow?
    private var observers: [NSObjectProtocol] = []

    init(onChange: @escaping @MainActor (Bool) -> Void) {
        self.onChange = onChange
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard trackedWindow !== window else {
            reportVisibility()
            return
        }

        stopObserving()
        trackedWindow = window
        guard let window else {
            onChange(false)
            return
        }

        let center = NotificationCenter.default
        let stateNotifications: [Notification.Name] = [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didBecomeMainNotification,
            NSWindow.didResignKeyNotification,
            NSWindow.didResignMainNotification,
            NSWindow.didMiniaturizeNotification,
            NSWindow.didDeminiaturizeNotification,
            NSWindow.didChangeOcclusionStateNotification,
        ]
        observers = stateNotifications.map { name in
            center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.reportVisibility()
                }
            }
        }
        observers.append(
            center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.onChange(false)
                }
            }
        )
        reportVisibility()
    }

    func reportVisibility() {
        guard let window = trackedWindow else {
            onChange(false)
            return
        }
        onChange(
            window.isVisible
                && !window.isMiniaturized
                && window.occlusionState.contains(.visible)
        )
    }

    func stopObserving() {
        let center = NotificationCenter.default
        observers.forEach(center.removeObserver)
        observers = []
    }

}
