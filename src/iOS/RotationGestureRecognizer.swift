class RotationGestureRecognizer: UIRotationGestureRecognizer {

    /// True when the rotation originated from a trackpad rather than direct touch.
    private(set) var isTrackpad = false

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        if #available(iOS 13.4, *) {
            isTrackpad = touches.contains { $0.type == .indirectPointer }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        isTrackpad = false
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        isTrackpad = false
    }
}