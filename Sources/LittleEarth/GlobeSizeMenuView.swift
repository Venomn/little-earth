import AppKit
import EarthCore

/// Inline in the main menu: no second menu window to overlap the slider.
final class GlobeSizeMenuView: NSView {
    static func menuItem(width: CGFloat, maximumWidth: CGFloat, language: AppLanguage,
                         onChange: @escaping (CGFloat) -> CGFloat) -> NSMenuItem {
        let item = NSMenuItem(title:L10n(language).text(.size),action:nil,keyEquivalent:"")
        item.isEnabled = true
        item.view = GlobeSizeMenuView(width:width,maximumWidth:maximumWidth,language:language,onChange:onChange)
        return item
    }
    let slider: NSSlider
    private let titleLabel = NSTextField(labelWithString:"")
    private let smallLabel = NSTextField(labelWithString:"")
    private let largeLabel = NSTextField(labelWithString:"")
    private let valueLabel = NSTextField(labelWithString:"")
    private let onChange: (CGFloat) -> CGFloat

    init(width: CGFloat, maximumWidth: CGFloat, language: AppLanguage,
         onChange: @escaping (CGFloat) -> CGFloat) {
        self.onChange = onChange
        slider = NSSlider(value:Double(width), minValue:Double(min(GlobeSizing.minimumWidth,maximumWidth)),
                          maxValue:Double(maximumWidth), target:nil, action:nil)
        super.init(frame:NSRect(x:0,y:0,width:260,height:84))
        autoresizingMask = [.width]
        let strings = L10n(language)
        titleLabel.stringValue = strings.text(.size)
        smallLabel.stringValue = strings.text(.small); largeLabel.stringValue = strings.text(.large)
        titleLabel.font = .menuFont(ofSize:0)
        for label in [smallLabel,largeLabel,valueLabel] {
            label.font = .systemFont(ofSize:11); label.textColor = .secondaryLabelColor
        }
        valueLabel.font = .monospacedDigitSystemFont(ofSize:11,weight:.regular)
        valueLabel.alignment = .right; largeLabel.alignment = .right
        for label in [titleLabel,smallLabel,largeLabel,valueLabel] { addSubview(label) }
        slider.isContinuous = true
        slider.setAccessibilityLabel(strings.text(.size))
        slider.toolTip = strings.text(.sizeHelp)
        slider.target = self; slider.action = #selector(changed)
        addSubview(slider)
        updateValue(width)
        layout()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var intrinsicContentSize: NSSize { NSSize(width:260,height:84) }
    override func layout() {
        super.layout()
        let width = bounds.width
        titleLabel.frame = NSRect(x:16,y:59,width:width-104,height:20)
        valueLabel.frame = NSRect(x:width-80,y:60,width:64,height:17)
        slider.frame = NSRect(x:16,y:29,width:width-32,height:24)
        smallLabel.frame = NSRect(x:16,y:9,width:80,height:16)
        largeLabel.frame = NSRect(x:width-96,y:9,width:80,height:16)
    }
    private func updateValue(_ width: CGFloat) {
        slider.doubleValue = Double(width)
        valueLabel.stringValue = "\(Int((width/240*100).rounded()))%"
    }
    @objc private func changed() {
        updateValue(onChange(CGFloat(slider.doubleValue)))
    }
}
