import AppKit
import EarthCore

struct PlaceCard: Equatable {
    var language: AppLanguage = .english
    let region: String
    let theme: String
    let title: String
    let body: String
    let weather: String
    let weatherDetails: String
    let sourceName: String?
    let sourceURL: URL?
}

final class WeatherDetailPopover: NSPopover {
    let cardController = WeatherDetailController()
    override init() {
        super.init()
        contentViewController = cardController
        // NSPopover retains its contentSize after the first presentation. A
        // manually sized view and preferredContentSize alone do not resize it.
        cardController.onContentSizeChange = { [weak self] size in
            self?.contentSize = size
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

final class WeatherDetailController: NSViewController {
    var onContentSizeChange: ((NSSize) -> Void)?
    private var card: PlaceCard?
    private var expanded = false
    private var weatherLabel: NSTextField?
    private var weatherDetailsLabel: NSTextField?
    private var elements = [(NSView, CGFloat, CGFloat)]()
    func update(_ card: PlaceCard, reset: Bool = false) {
        if self.card == card && !reset { return }
        let previous = self.card
        self.card = card
        // A timer refresh must not recreate the text/buttons the user is reading.
        if !reset, let previous, previous.language == card.language,
           previous.region == card.region, previous.theme == card.theme,
           previous.title == card.title, previous.body == card.body,
           previous.sourceName == card.sourceName, previous.sourceURL == card.sourceURL {
            weatherLabel?.stringValue = card.weather
            weatherDetailsLabel?.stringValue = card.weatherDetails
            layoutElements()
            return
        }
        if reset { expanded = false }
        _ = view
        render()
    }
    override func loadView() {
        view = NSView(frame:NSRect(x:0,y:0,width:304,height:250))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(red:0.97,green:0.955,blue:0.92,alpha:1).cgColor
        view.appearance = NSAppearance(named:.aqua)
    }
    private func render() {
        guard let card else { return }
        let strings = L10n(card.language)
        view.subviews.forEach { $0.removeFromSuperview() }
        elements.removeAll(); weatherLabel = nil; weatherDetailsLabel = nil
        @discardableResult func label(_ value: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = NSColor(red:0.24,green:0.26,blue:0.23,alpha:1), gap: CGFloat = 8) -> NSTextField {
            let text = NSTextField(wrappingLabelWithString:value)
            text.font = .systemFont(ofSize:size,weight:weight); text.textColor = color
            text.isSelectable = true
            elements.append((text,0,gap)); return text
        }
        label(card.region,size:11,weight:.medium,color:.secondaryLabelColor,gap:5)
        label(card.theme,size:10,weight:.medium,color:NSColor(red:0.42,green:0.48,blue:0.37,alpha:1),gap:11)
        label(card.title,size:19,weight:.semibold,gap:10)
        label(card.body,size:13,gap:15)
        let rule = NSBox(); rule.boxType = .separator
        elements.append((rule,1,10))
        weatherLabel = label(card.weather,size:11,gap:6)
        let toggle = NSButton(title:strings.text(expanded ? .collapseWeather:.expandWeather),target:self,action:#selector(toggleWeather))
        toggle.isBordered = false; toggle.alignment = .left; toggle.font = .systemFont(ofSize:11)
        toggle.contentTintColor = NSColor(red:0.35,green:0.43,blue:0.45,alpha:1)
        elements.append((toggle,22,8))
        if expanded { weatherDetailsLabel = label(card.weatherDetails,size:11,color:.secondaryLabelColor,gap:10) }
        if let source = card.sourceName, let url = card.sourceURL {
            let button = NSButton(title:strings.format(.cultureSource,source),target:self,action:#selector(openSource))
            button.isBordered = false; button.alignment = .left; button.font = .systemFont(ofSize:10)
            button.contentTintColor = .secondaryLabelColor; button.toolTip = url.absoluteString
            button.setAccessibilityHelp(strings.text(.cultureSourceHelp))
            elements.append((button,22,0))
        }
        layoutElements()
    }
    private func layoutElements() {
        let width: CGFloat = 268
        let measured = elements.map { (element,height,gap) -> (NSView,CGFloat,CGFloat) in
            if let text = element as? NSTextField {
                return (text,ceil(text.cell!.cellSize(forBounds:NSRect(x:0,y:0,width:width,height:2000)).height)+2,gap)
            }
            return (element,height,gap)
        }
        let total = measured.reduce(CGFloat(28)) { $0+$1.1+$1.2 }
        let size = NSSize(width:304,height:total)
        // Resize the host before its view. With animations disabled, AppKit
        // otherwise treats the already-updated view size as a no-op and keeps
        // the old popover window frame.
        onContentSizeChange?(size)
        view.setFrameSize(size)
        var y = total-18
        for (element,height,gap) in measured {
            y -= height; element.frame = NSRect(x:18,y:y,width:width,height:height)
            if element.superview == nil { view.addSubview(element) }; y -= gap
        }
        preferredContentSize = view.frame.size
    }
    @objc private func toggleWeather() { expanded.toggle(); render() }
    @objc private func openSource() { if let url = card?.sourceURL { NSWorkspace.shared.open(url) } }
}
