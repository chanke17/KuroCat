import Foundation
import AppKit

// MARK: - Live Animated Cat Preview View inside Editor

final class CatEditorPreviewView: NSView {
    let previewPhysics = CatPhysics()
    private var timer: Timer?
    private var lastTime: CFTimeInterval = CACurrentMediaTime()

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func startAnimating() {
        stopAnimating()
        lastTime = CACurrentMediaTime()
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let now = CACurrentMediaTime()
            let dt = CGFloat(now - self.lastTime)
            self.lastTime = now
            let dummyFrame = CGRect(x: 0, y: 0, width: 360, height: 320)
            let scripted = ScriptedFrameInput(
                now: now,
                activeKeys: [],
                orderedKeys: [],
                mouseScreenPos: CGPoint(x: 180 + sin(now * 1.1) * 90, y: 180 + cos(now * 0.8) * 35),
                mouseVelocity: .zero,
                leftMouseDown: false,
                rightMouseDown: false,
                lastMouseMoveTime: now - 3.0,
                lastMouseClickTime: 0,
                lastKeyActivityTime: 0
            )
            self.previewPhysics.step(dt: dt, windowFrameInScreen: dummyFrame, scripted: scripted)
            self.needsDisplay = true
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stopAnimating() {
        timer?.invalidate()
        timer = nil
    }

    func triggerBouncePreview() {
        previewPhysics.bodyShiftX.velocity += 140
        previewPhysics.headTilt.velocity += 2.6
        previewPhysics.bodySquash.velocity -= 1.8
        previewPhysics.furSwayX.velocity -= 28
        previewPhysics.furSwayY.velocity += 24
        previewPhysics.earTwitch.velocity += 4.5
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(bounds)

        // Subtle studio backdrop gradient
        let cs = CGColorSpaceCreateDeviceRGB()
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let topC = isDark
            ? NSColor(calibratedRed: 0.19, green: 0.20, blue: 0.23, alpha: 1.0)
            : NSColor(calibratedRed: 0.93, green: 0.94, blue: 0.96, alpha: 1.0)
        let botC = isDark
            ? NSColor(calibratedRed: 0.14, green: 0.15, blue: 0.18, alpha: 1.0)
            : NSColor(calibratedRed: 0.87, green: 0.89, blue: 0.92, alpha: 1.0)
        if let grad = CGGradient(colorsSpace: cs, colors: [topC.cgColor, botC.cgColor] as CFArray, locations: [0, 1]) {
            ctx.drawLinearGradient(grad, start: .zero, end: CGPoint(x: 0, y: bounds.height), options: [])
        }

        // Fit 360x320 canvas centered inside preview box
        let scale = min(bounds.width / CatPhysics.canvasSize.width, bounds.height / CatPhysics.canvasSize.height) * 1.12
        let dx = (bounds.width - CatPhysics.canvasSize.width * scale) * 0.5
        let dy = (bounds.height - CatPhysics.canvasSize.height * scale) * 0.5 - 6

        ctx.saveGState()
        ctx.translateBy(x: dx, y: dy)
        ctx.scaleBy(x: scale, y: scale)
        CatRenderer.draw(in: ctx, physics: previewPhysics, showPermissionPill: false)
        ctx.restoreGState()
    }
}

// MARK: - Native Custom Cat Editor Window Controller

final class CatEditorWindowController: NSWindowController, NSWindowDelegate {
    static let shared = CatEditorWindowController()

    private let previewView = CatEditorPreviewView()
    private var presetButtons: [CatBreedPreset: NSButton] = [:]
    private let presetHeaderLabel = NSTextField(labelWithString: "")
    private let styleHeaderLabel = NSTextField(labelWithString: "")
    private let patLbl = NSTextField(labelWithString: "")
    private let furLbl = NSTextField(labelWithString: "")
    private let shortBtn = NSButton(title: "", target: nil, action: nil)
    private let medBtn = NSButton(title: "", target: nil, action: nil)
    private let longBtn = NSButton(title: "", target: nil, action: nil)
    private let colorHeaderLabel = NSTextField(labelWithString: "")
    private let eyeLabel = NSTextField(labelWithString: "")
    private let bounceBtn = NSButton(title: "", target: nil, action: nil)
    private let randomBtn = NSButton(title: "", target: nil, action: nil)
    private let doneBtn = NSButton(title: "", target: nil, action: nil)
    private let patternPopup = NSPopUpButton()
    private let furSlider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let furValueLabel = NSTextField(labelWithString: "")

    private let primaryLabel = NSTextField(labelWithString: "")
    private let primaryWell = NSColorWell()
    private let secondaryRow = NSStackView()
    private let secondaryLabel = NSTextField(labelWithString: "")
    private let secondaryWell = NSColorWell()
    private let tertiaryRow = NSStackView()
    private let tertiaryLabel = NSTextField(labelWithString: "")
    private let tertiaryWell = NSColorWell()
    private let eyeWell = NSColorWell()

    private init() {
        let win = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 460, height: 610),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.title = L10n.tr("🐱 KuroCat Custom Studio", "🐱 自定义猫咪编辑器 (KuroCat Studio)")
        win.level = .floating
        win.isReleasedWhenClosed = false
        win.center()

        super.init(window: win)
        win.delegate = self
        buildUI(in: win)
        refreshLocalizedStrings()
        syncUIFromSettings()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func showEditor() {
        refreshLocalizedStrings()
        syncUIFromSettings()
        previewView.startAnimating()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func refreshLocalizedStrings() {
        window?.title = L10n.tr("🐱 KuroCat Custom Studio", "🐱 自定义猫咪编辑器 (KuroCat Studio)")
        presetHeaderLabel.stringValue = L10n.tr("Breed Presets (1-Click Apply, Freely Customizable)", "品种预设 (一键套用，也可继续自定义)")
        styleHeaderLabel.stringValue = L10n.tr("Fur Pattern & Length (with Physics)", "毛发花纹与长短毛物理")
        patLbl.stringValue = L10n.tr("Pattern:", "花纹类型:")
        furLbl.stringValue = L10n.tr("Fur Length:", "毛发长度:")
        shortBtn.title = L10n.tr("Short", "短")
        medBtn.title = L10n.tr("Med", "中")
        longBtn.title = L10n.tr("Long", "长")
        colorHeaderLabel.stringValue = L10n.tr("Custom Colors (Click Swatch for Full Color Picker)", "自定义配色 (点击色块打开完整取色器)")
        eyeLabel.stringValue = L10n.tr("Eye Color", "瞳色")
        bounceBtn.title = L10n.tr("✨ Test Fur Physics", "✨ 测试毛发晃动")
        randomBtn.title = L10n.tr("🎲 Randomize", "🎲 随机配色")
        doneBtn.title = L10n.tr("Done", "完成")

        for (preset, btn) in presetButtons {
            btn.title = preset.shortName
            btn.toolTip = preset.displayName
        }

        let selIdx = patternPopup.indexOfSelectedItem
        patternPopup.removeAllItems()
        for pat in FurPattern.allCases {
            patternPopup.addItem(withTitle: pat.displayName)
        }
        if selIdx >= 0 && selIdx < FurPattern.allCases.count {
            patternPopup.selectItem(at: selIdx)
        }
        syncUIFromSettings()
    }

    func windowWillClose(_ notification: Notification) {
        previewView.stopAnimating()
    }

    // MARK: - UI Construction

    private func buildUI(in win: NSWindow) {
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 12
        root.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        root.translatesAutoresizingMaskIntoConstraints = false

        guard let contentView = win.contentView else { return }
        contentView.addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: contentView.topAnchor),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
        ])

        // 1. Live Preview Box
        previewView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            previewView.widthAnchor.constraint(equalToConstant: 428),
            previewView.heightAnchor.constraint(equalToConstant: 175)
        ])
        root.addArrangedSubview(previewView)

        // 2. Breed Presets (First Priority!)
        presetHeaderLabel.font = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
        presetHeaderLabel.textColor = .labelColor
        root.addArrangedSubview(presetHeaderLabel)

        let presetGrid = NSStackView()
        presetGrid.orientation = .vertical
        presetGrid.spacing = 6
        presetGrid.alignment = .leading

        let allPresets = CatBreedPreset.allCases
        let perRow = 5
        var idx = 0
        while idx < allPresets.count {
            let row = NSStackView()
            row.orientation = .horizontal
            row.spacing = 6
            row.distribution = .fillEqually
            for j in idx..<min(idx + perRow, allPresets.count) {
                let preset = allPresets[j]
                let btn = NSButton(title: preset.shortName, target: self, action: #selector(presetTapped(_:)))
                btn.bezelStyle = .rounded
                btn.font = NSFont.systemFont(ofSize: 11, weight: .medium)
                btn.tag = j
                btn.toolTip = preset.displayName
                presetButtons[preset] = btn
                row.addArrangedSubview(btn)
            }
            row.translatesAutoresizingMaskIntoConstraints = false
            row.widthAnchor.constraint(equalToConstant: 428).isActive = true
            presetGrid.addArrangedSubview(row)
            idx += perRow
        }
        root.addArrangedSubview(presetGrid)

        root.addArrangedSubview(makeSeparator())

        // 3. Fur Pattern & Fur Length (with Physics)
        styleHeaderLabel.font = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
        styleHeaderLabel.textColor = .labelColor
        root.addArrangedSubview(styleHeaderLabel)

        let patternRow = NSStackView()
        patternRow.orientation = .horizontal
        patternRow.spacing = 10
        patternRow.alignment = .centerY
        patLbl.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        patLbl.widthAnchor.constraint(equalToConstant: 78).isActive = true
        for pat in FurPattern.allCases {
            patternPopup.addItem(withTitle: pat.displayName)
        }
        patternPopup.target = self
        patternPopup.action = #selector(patternChanged(_:))
        patternRow.addArrangedSubview(patLbl)
        patternRow.addArrangedSubview(patternPopup)
        root.addArrangedSubview(patternRow)

        let furRow = NSStackView()
        furRow.orientation = .horizontal
        furRow.spacing = 6
        furRow.alignment = .centerY
        furLbl.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        furLbl.widthAnchor.constraint(equalToConstant: 78).isActive = true
        furSlider.target = self
        furSlider.action = #selector(furLengthChanged(_:))
        furSlider.isContinuous = true
        furSlider.widthAnchor.constraint(equalToConstant: 145).isActive = true
        furValueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        furValueLabel.textColor = .secondaryLabelColor
        furValueLabel.widthAnchor.constraint(equalToConstant: 76).isActive = true

        shortBtn.target = self; shortBtn.action = #selector(setShortFur); shortBtn.bezelStyle = .rounded; shortBtn.controlSize = .small
        medBtn.target = self; medBtn.action = #selector(setMedFur); medBtn.bezelStyle = .rounded; medBtn.controlSize = .small
        longBtn.target = self; longBtn.action = #selector(setLongFur); longBtn.bezelStyle = .rounded; longBtn.controlSize = .small

        furRow.addArrangedSubview(furLbl)
        furRow.addArrangedSubview(furSlider)
        furRow.addArrangedSubview(furValueLabel)
        furRow.addArrangedSubview(shortBtn)
        furRow.addArrangedSubview(medBtn)
        furRow.addArrangedSubview(longBtn)
        root.addArrangedSubview(furRow)

        root.addArrangedSubview(makeSeparator())

        // 4. Multi-Color Pickers (NSColorWell -> Full macOS Color Panel!)
        colorHeaderLabel.font = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
        colorHeaderLabel.textColor = .labelColor
        root.addArrangedSubview(colorHeaderLabel)

        let primaryRow = makeColorRow(label: primaryLabel, well: primaryWell, action: #selector(primaryColorChanged(_:)))
        root.addArrangedSubview(primaryRow)

        configureColorRow(secondaryRow, label: secondaryLabel, well: secondaryWell, action: #selector(secondaryColorChanged(_:)))
        root.addArrangedSubview(secondaryRow)

        configureColorRow(tertiaryRow, label: tertiaryLabel, well: tertiaryWell, action: #selector(tertiaryColorChanged(_:)))
        root.addArrangedSubview(tertiaryRow)

        let eyeRow = makeColorRow(label: eyeLabel, well: eyeWell, action: #selector(eyeColorChanged(_:)))
        root.addArrangedSubview(eyeRow)

        // Spacer
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        root.addArrangedSubview(spacer)

        // 5. Footer Buttons
        let footer = NSStackView()
        footer.orientation = .horizontal
        footer.spacing = 8
        footer.alignment = .centerY
        footer.translatesAutoresizingMaskIntoConstraints = false
        footer.widthAnchor.constraint(equalToConstant: 428).isActive = true

        bounceBtn.target = self; bounceBtn.action = #selector(testPhysicsTapped); bounceBtn.bezelStyle = .rounded
        randomBtn.target = self; randomBtn.action = #selector(randomizeTapped); randomBtn.bezelStyle = .rounded

        let flex = NSView()
        flex.setContentHuggingPriority(.defaultLow, for: .horizontal)

        doneBtn.target = self; doneBtn.action = #selector(closeTapped); doneBtn.bezelStyle = .rounded; doneBtn.keyEquivalent = "\r"

        footer.addArrangedSubview(bounceBtn)
        footer.addArrangedSubview(randomBtn)
        footer.addArrangedSubview(flex)
        footer.addArrangedSubview(doneBtn)
        root.addArrangedSubview(footer)
    }

    private func makeSectionTitle(_ title: String) -> NSTextField {
        let lbl = NSTextField(labelWithString: title)
        lbl.font = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
        lbl.textColor = .labelColor
        return lbl
    }

    private func makeSeparator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        box.widthAnchor.constraint(equalToConstant: 428).isActive = true
        return box
    }

    private func makeColorRow(label: NSTextField, well: NSColorWell, action: Selector) -> NSStackView {
        let row = NSStackView()
        configureColorRow(row, label: label, well: well, action: action)
        return row
    }

    private func configureColorRow(_ row: NSStackView, label: NSTextField, well: NSColorWell, action: Selector) {
        row.orientation = .horizontal
        row.spacing = 10
        row.alignment = .centerY
        label.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(equalToConstant: 155).isActive = true

        well.target = self
        well.action = action
        well.translatesAutoresizingMaskIntoConstraints = false
        well.widthAnchor.constraint(equalToConstant: 56).isActive = true
        well.heightAnchor.constraint(equalToConstant: 24).isActive = true

        row.addArrangedSubview(label)
        row.addArrangedSubview(well)
    }

    // MARK: - Sync UI <-> CatSettings.shared.appearance

    func syncUIFromSettings() {
        let app = CatSettings.shared.appearance

        // Highlight active preset button
        for (preset, btn) in presetButtons {
            let isMatch = (app.presetID == preset.rawValue)
            btn.contentTintColor = isMatch ? .controlAccentColor : nil
        }

        if let patIdx = FurPattern.allCases.firstIndex(of: app.pattern) {
            patternPopup.selectItem(at: patIdx)
        }

        furSlider.doubleValue = Double(app.furLength)
        updateFurLabel(app.furLength)

        primaryLabel.stringValue = app.pattern.primaryLabel
        secondaryLabel.stringValue = app.pattern.secondaryLabel
        tertiaryLabel.stringValue = app.pattern.tertiaryLabel

        primaryWell.color = app.primaryColor.nsColor
        secondaryWell.color = app.secondaryColor.nsColor
        tertiaryWell.color = app.tertiaryColor.nsColor
        eyeWell.color = app.eyeColor.nsColor

        secondaryRow.isHidden = app.pattern.colorSlotCount < 2
        tertiaryRow.isHidden = app.pattern.colorSlotCount < 3

        previewView.needsDisplay = true
    }

    private func updateFurLabel(_ val: CGFloat) {
        let pct = Int(round(val * 100))
        let desc: String
        if val < 0.30 {
            desc = L10n.tr("Short", "短毛")
        } else if val < 0.65 {
            desc = L10n.tr("Medium", "中毛")
        } else {
            desc = L10n.tr("Fluffy", "长毛蓬松")
        }
        furValueLabel.stringValue = "\(desc) (\(pct)%)"
    }

    // MARK: - Actions

    @objc private func presetTapped(_ sender: NSButton) {
        let presets = CatBreedPreset.allCases
        guard sender.tag >= 0 && sender.tag < presets.count else { return }
        CatSettings.shared.appearance = presets[sender.tag].appearance
        syncUIFromSettings()
        previewView.triggerBouncePreview()
    }

    @objc private func patternChanged(_ sender: NSPopUpButton) {
        let idx = sender.indexOfSelectedItem
        guard idx >= 0 && idx < FurPattern.allCases.count else { return }
        var app = CatSettings.shared.appearance
        app.pattern = FurPattern.allCases[idx]
        app.presetID = nil
        CatSettings.shared.appearance = app
        syncUIFromSettings()
    }

    @objc private func furLengthChanged(_ sender: NSSlider) {
        var app = CatSettings.shared.appearance
        app.furLength = CGFloat(sender.doubleValue)
        app.presetID = nil
        CatSettings.shared.appearance = app
        updateFurLabel(app.furLength)
        previewView.needsDisplay = true
    }

    @objc private func setShortFur() {
        furSlider.doubleValue = 0.0
        furLengthChanged(furSlider)
        previewView.triggerBouncePreview()
    }

    @objc private func setMedFur() {
        furSlider.doubleValue = 0.45
        furLengthChanged(furSlider)
        previewView.triggerBouncePreview()
    }

    @objc private func setLongFur() {
        furSlider.doubleValue = 1.0
        furLengthChanged(furSlider)
        previewView.triggerBouncePreview()
    }

    @objc private func primaryColorChanged(_ sender: NSColorWell) {
        var app = CatSettings.shared.appearance
        app.primaryColor = RGBAColor(sender.color)
        app.presetID = nil
        CatSettings.shared.appearance = app
        previewView.needsDisplay = true
    }

    @objc private func secondaryColorChanged(_ sender: NSColorWell) {
        var app = CatSettings.shared.appearance
        app.secondaryColor = RGBAColor(sender.color)
        app.presetID = nil
        CatSettings.shared.appearance = app
        previewView.needsDisplay = true
    }

    @objc private func tertiaryColorChanged(_ sender: NSColorWell) {
        var app = CatSettings.shared.appearance
        app.tertiaryColor = RGBAColor(sender.color)
        app.presetID = nil
        CatSettings.shared.appearance = app
        previewView.needsDisplay = true
    }

    @objc private func eyeColorChanged(_ sender: NSColorWell) {
        var app = CatSettings.shared.appearance
        app.eyeColor = RGBAColor(sender.color)
        app.presetID = nil
        CatSettings.shared.appearance = app
        previewView.needsDisplay = true
    }

    @objc private func testPhysicsTapped() {
        previewView.triggerBouncePreview()
    }

    @objc private func randomizeTapped() {
        let basePreset = CatBreedPreset.allCases.randomElement() ?? .orangeTabby
        var app = basePreset.appearance
        app.pattern = FurPattern.allCases.randomElement() ?? .tabby
        app.furLength = CGFloat([0.0, 0.25, 0.55, 0.92].randomElement() ?? 0.25)
        app.presetID = nil
        // Slight tasteful hue shift
        let shift = CGFloat.random(in: -0.06...0.06)
        func jitter(_ c: RGBAColor) -> RGBAColor {
            RGBAColor(
                r: max(0.06, min(0.98, c.r + shift)),
                g: max(0.06, min(0.98, c.g - shift * 0.5)),
                b: max(0.06, min(0.98, c.b + shift * 0.7))
            )
        }
        app.primaryColor = jitter(app.primaryColor)
        app.secondaryColor = jitter(app.secondaryColor)
        CatSettings.shared.appearance = app
        syncUIFromSettings()
        previewView.triggerBouncePreview()
    }

    @objc private func closeTapped() {
        window?.close()
    }
}
