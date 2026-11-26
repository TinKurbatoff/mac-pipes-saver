import AppKit
import ScreenSaver
import SceneKit

@objc(PipesSaverView)
final class PipesSaverView: ScreenSaverView {
    private var scnView: SCNView?
    private var engine: PipesEngine?
    private var configController: ConfigSheetController?
    private var stopObserver: NSObjectProtocol?

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    deinit {
        if let o = stopObserver { DistributedNotificationCenter.default().removeObserver(o) }
    }

    private func setUp() {
        animationTimeInterval = 1.0 / 30.0
        wantsLayer = true

        let engine = PipesEngine(settings: PipesSettings.load(), viewSize: bounds.size)
        let view = SCNView(frame: bounds)
        view.autoresizingMask = [.width, .height]
        view.backgroundColor = .black
        view.antialiasingMode = isPreview ? .multisampling2X : .multisampling4X
        view.preferredFramesPerSecond = 60
        view.rendersContinuously = true
        view.allowsCameraControl = false
        view.scene = engine.scene
        view.pointOfView = engine.cameraNode
        view.overlaySKScene = engine.overlay
        view.delegate = engine
        view.isPlaying = false
        addSubview(view)

        self.engine = engine
        self.scnView = view

        // macOS 14+ keeps the legacy screen saver host alive after the saver is dismissed,
        // so stop rendering (and let the host process exit) when the system says it stopped.
        stopObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screensaver.willstop"), object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.scnView?.isPlaying = false
            if !self.isPreview {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { exit(0) }
            }
        }
    }

    override func startAnimation() {
        super.startAnimation()
        scnView?.isPlaying = true
    }

    override func stopAnimation() {
        super.stopAnimation()
        scnView?.isPlaying = false
    }

    override func animateOneFrame() {
        // SceneKit drives rendering; nothing to do here.
    }

    override func draw(_ rect: NSRect) {
        NSColor.black.setFill()
        rect.fill()
    }

    // MARK: Options sheet

    override var hasConfigureSheet: Bool { true }

    override var configureSheet: NSWindow? {
        let controller = ConfigSheetController(settings: PipesSettings.load()) { [weak self] newSettings in
            newSettings.save()
            self?.engine?.apply(settings: newSettings)
        }
        configController = controller
        return controller.window
    }
}

/// Programmatic options sheet (no nib needed).
final class ConfigSheetController: NSObject {
    let window: NSWindow
    private var settings: PipesSettings
    private let onSave: (PipesSettings) -> Void

    private let jointsPopup = NSPopUpButton()
    private let speedSlider = NSSlider()
    private let speedLabel = NSTextField(labelWithString: "")
    private let countSlider = NSSlider()
    private let countLabel = NSTextField(labelWithString: "")
    private let intervalSlider = NSSlider()
    private let intervalLabel = NSTextField(labelWithString: "")
    private let rotateCheck = NSButton(checkboxWithTitle: "Slowly rotate the camera", target: nil, action: nil)
    private let teapotCheck = NSButton(checkboxWithTitle: "Teapots (easter egg)", target: nil, action: nil)

    init(settings: PipesSettings, onSave: @escaping (PipesSettings) -> Void) {
        self.settings = settings
        self.onSave = onSave
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 280),
                          styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "Pipes Options"
        super.init()
        buildUI()
        refresh()
    }

    private func buildUI() {
        PipesSettings.Joints.allCases.forEach { jointsPopup.addItem(withTitle: $0.title) }

        speedSlider.minValue = PipesSettings.speedRange.lowerBound
        speedSlider.maxValue = PipesSettings.speedRange.upperBound
        countSlider.minValue = Double(PipesSettings.pipeCountRange.lowerBound)
        countSlider.maxValue = Double(PipesSettings.pipeCountRange.upperBound)
        countSlider.numberOfTickMarks = PipesSettings.pipeCountRange.count
        countSlider.allowsTickMarkValuesOnly = true
        intervalSlider.minValue = PipesSettings.resetIntervalRange.lowerBound
        intervalSlider.maxValue = PipesSettings.resetIntervalRange.upperBound

        for control in [speedSlider, countSlider, intervalSlider] as [NSControl] {
            control.target = self
            control.action = #selector(controlChanged(_:))
        }
        for label in [speedLabel, countLabel, intervalLabel] {
            label.alignment = .right
            label.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            label.widthAnchor.constraint(equalToConstant: 60).isActive = true
        }
        for s in [speedSlider, countSlider, intervalSlider] {
            s.widthAnchor.constraint(equalToConstant: 200).isActive = true
        }

        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Joints:"), jointsPopup, NSGridCell.emptyContentView],
            [NSTextField(labelWithString: "Growth speed:"), speedSlider, speedLabel],
            [NSTextField(labelWithString: "Pipes at once:"), countSlider, countLabel],
            [NSTextField(labelWithString: "Reset every:"), intervalSlider, intervalLabel],
            [NSGridCell.emptyContentView, rotateCheck, NSGridCell.emptyContentView],
            [NSGridCell.emptyContentView, teapotCheck, NSGridCell.emptyContentView],
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.rowSpacing = 10
        grid.columnSpacing = 8

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel(_:)))
        cancel.keyEquivalent = "\u{1b}"
        let ok = NSButton(title: "OK", target: self, action: #selector(ok(_:)))
        ok.keyEquivalent = "\r"
        let buttons = NSStackView(views: [cancel, ok])

        let footer = NSTextField(labelWithString: "Native, offline build — no network access.")
        footer.textColor = .secondaryLabelColor
        footer.font = .systemFont(ofSize: NSFont.smallSystemFontSize)

        let stack = NSStackView(views: [grid, footer, buttons])
        stack.orientation = .vertical
        stack.alignment = .trailing
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.setCustomSpacing(18, after: grid)
        window.contentView = stack
    }

    private func refresh() {
        jointsPopup.selectItem(at: settings.joints.rawValue)
        speedSlider.doubleValue = settings.speed
        countSlider.integerValue = settings.pipeCount
        intervalSlider.doubleValue = settings.resetInterval
        rotateCheck.state = settings.rotateCamera ? .on : .off
        teapotCheck.state = settings.teapots ? .on : .off
        updateLabels()
    }

    private func updateLabels() {
        speedLabel.stringValue = "\(Int(speedSlider.doubleValue.rounded()))/s"
        countLabel.stringValue = "\(countSlider.integerValue)"
        intervalLabel.stringValue = "\(Int(intervalSlider.doubleValue.rounded())) s"
    }

    @objc private func controlChanged(_ sender: Any?) { updateLabels() }

    @objc private func ok(_ sender: Any?) {
        settings.joints = PipesSettings.Joints(rawValue: jointsPopup.indexOfSelectedItem) ?? .mixed
        settings.speed = speedSlider.doubleValue.rounded()
        settings.pipeCount = countSlider.integerValue
        settings.resetInterval = intervalSlider.doubleValue.rounded()
        settings.rotateCamera = rotateCheck.state == .on
        settings.teapots = teapotCheck.state == .on
        onSave(settings)
        close()
    }

    @objc private func cancel(_ sender: Any?) { close() }

    private func close() {
        if let parent = window.sheetParent {
            parent.endSheet(window)
        } else {
            window.close()
        }
    }
}
