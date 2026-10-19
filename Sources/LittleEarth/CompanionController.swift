import AppKit
import EarthCore

final class CompanionPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor final class CompanionController: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    private var panel: CompanionPanel!
    private var globeView: GlobeView!
    private var status: NSStatusItem!
    private let menu = NSMenu()
    private var isMenuOpen = false
    private let weather = WeatherStore()
    private let vessels = LocalVesselStore()
    private var renderedVessels = [VesselSample]()
    private var selectedVesselID: String?
    private let detail = WeatherDetailPopover()
    private var detailDismissal: PopoverDismissal?
    private var detailContent: WeatherDetailController { detail.cardController }
    private var selectedCoordinate: GeoCoordinate?
    private let atlas = try? PlaceAtlas.bundled()
    private let cultures = try? CultureCatalog.bundled()
    private let marine = try? MarineCatalog.bundled()
    private var renderedWeather = [WeatherSample]()

    private var observers = [NSObjectProtocol]()
    private var isHidden = false
    private var sleeping = false
    private var screenSleeping = false
    private var locked = false
    private let defaults = UserDefaults.standard
    private var language = AppLanguage.saved()
    private var strings: L10n { L10n(language) }
    private var floating = true
    private var globeSize: CGFloat = 160

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let savedSize = defaults.double(forKey: "globeSize")
        globeSize = GlobeSizing.restoredWidth(savedGlobeSize:savedSize)/1.5
        floating = defaults.object(forKey: "floating") == nil ? true : defaults.bool(forKey: "floating")
        let width = globeSize*1.5
        panel = CompanionPanel(contentRect: NSRect(x: 0,y: 0,width: width,height: width),
                               styleMask: [.borderless,.nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = strings.text(.appName)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        panel.level = floating ? .floating : .normal
        panel.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary,.stationary,.ignoresCycle]
        panel.isMovableByWindowBackground = false
        panel.delegate = self
        let content = NSView(frame: NSRect(origin: .zero, size: panel.frame.size))
        globeView = GlobeView(frame: NSRect(x: 0,y: 0,width: width,height: width))
        globeView.autoresizingMask = [.width,.height]
        content.addSubview(globeView)
        detailDismissal = PopoverDismissal(popover:detail,onOutsideClick:{ [weak self] event in
            guard let self, event.type == .leftMouseDown, event.window === self.panel else { return }
            self.globeView.suppressSelection(for:event)
        },onClose:{ [weak self] in
            self?.selectedCoordinate = nil
            self?.selectedVesselID = nil
            self?.globeView.setAutoRotationPaused(false)
        },onShow:{ [weak self] in self?.globeView.setAutoRotationPaused(true) })
        globeView.onSelect = { [weak self] coordinate, point in self?.showWeather(at:coordinate,point:point) }
        globeView.onSelectVessel = { [weak self] id, point in self?.showVessel(id,at:point) }
        vessels.onChange = { [weak self] in self?.vesselsChanged() }
        weather.onChange = { [weak self] in self?.weatherChanged() }

        panel.contentView = content
        globeView.onPointerUpdate = { [weak self] in self?.updatePointerPassthrough() }
        menu.delegate = self
        buildMenu()
        globeView.menu = menu
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "globe.asia.australia.fill", accessibilityDescription: strings.text(.appName))
        status.button?.toolTip = strings.text(.appName)
        applyLanguage()
        status.menu = menu
        restorePosition()
        observeLifecycle()
        panel.orderFrontRegardless()
        updateRunning()
    }

    private func buildMenu() {
        // Weather and vessel updates must not replace an NSSlider while the
        // user is dragging it in the menu's tracking run loop.
        guard !isMenuOpen else { return }
        menu.removeAllItems()
        let title = NSMenuItem(title: strings.text(.appName), action: nil, keyEquivalent: "")
        title.isEnabled = false; menu.addItem(title)
        let hint = NSMenuItem(title: strings.text(.menuHint), action: nil, keyEquivalent: "")
        hint.isEnabled = false; menu.addItem(hint)
        menu.addItem(.separator())
        add(strings.text(isHidden ? .showEarth:.hideEarth), #selector(toggleVisibility))
        add(strings.text(.resetPosition), #selector(resetPosition))
        let pin = add(strings.text(.alwaysOnTop), #selector(toggleFloating)); pin.state = floating ? .on : .off
        let available = (panel.screen ?? NSScreen.main)?.visibleFrame.size ?? NSSize(width:660,height:660)
        let sizeControl = GlobeSizeMenuView.menuItem(width:panel.frame.width,
            maximumWidth:min(GlobeSizing.maximumWidth,available.width,available.height),language:language) { [weak self] width in
                self?.changeSize(to:width) ?? width
            }
        menu.addItem(sizeControl)
        menu.addItem(.separator())
        let languageItem = NSMenuItem(title:strings.text(.language),action:nil,keyEquivalent:"")
        let languages = NSMenu()
        for choice in AppLanguage.allCases {
            let item = NSMenuItem(title:choice.displayName,action:#selector(changeLanguage(_:)),keyEquivalent:"")
            item.target = self; item.representedObject = choice.rawValue
            item.state = choice == language ? .on:.off
            languages.addItem(item)
        }
        languageItem.submenu = languages; menu.addItem(languageItem)
        menu.addItem(.separator())
        let weatherState = NSMenuItem(title:weather.statusText(in:language),action:nil,keyEquivalent:"")
        weatherState.isEnabled = false; weatherState.toolTip = strings.text(.weatherHelp); menu.addItem(weatherState)
        add(strings.text(.refreshWeather), #selector(refreshWeather))
        add(strings.text(.weatherSource), #selector(openWeatherSource))
        menu.addItem(.separator())
        let shipState = NSMenuItem(title:vessels.statusText(in:language),action:nil,keyEquivalent:"")
        shipState.isEnabled = false; menu.addItem(shipState)
        add(strings.text(.shipsSetup), #selector(configureVessels))
        menu.addItem(.separator())
        add(strings.text(.quit), #selector(quit), key: "q")
    }
    func menuNeedsUpdate(_ menu: NSMenu) { buildMenu() }
    func menuWillOpen(_ menu: NSMenu) { isMenuOpen = true }
    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
        DispatchQueue.main.async { [weak self] in self?.buildMenu() }
    }
    @discardableResult private func add(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self; menu.addItem(item); return item
    }
    @objc private func changeLanguage(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let selected = AppLanguage(rawValue:raw) else { return }
        language = selected; language.save(in:defaults)
        applyLanguage()
    }
    private func applyLanguage() {
        panel.title = strings.text(.appName)
        status.button?.toolTip = strings.text(.appName)
        status.button?.setAccessibilityLabel(strings.text(.appName))
        globeView.setLanguage(language)
        weatherChanged()
    }
    @objc private func toggleVisibility() {
        isHidden.toggle()
        if isHidden { panel.orderOut(nil) } else { keepVisible(); panel.orderFrontRegardless() }
        updateRunning(); buildMenu()
    }
    @objc private func toggleFloating() {
        floating.toggle(); panel.level = floating ? .floating : .normal
        defaults.set(floating, forKey: "floating"); buildMenu()
    }
    private func changeSize(to width: CGFloat) -> CGFloat {
        detail.close(); globeView.finishDrag()
        var frame = panel.frame
        frame.origin.x += (frame.width-width)/2
        frame.origin.y += (frame.height-width)/2
        frame.size = NSSize(width: width,height: width)
        panel.setFrame(frame, display: true)
        keepVisible(); savePosition()
        return panel.frame.width
    }
    @objc private func resetPosition() {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else { return }
        var frame = panel.frame
        frame.origin = NSPoint(x: screen.visibleFrame.maxX-frame.width-30, y: screen.visibleFrame.minY+40)
        panel.setFrame(GlobeSizing.fitting(frame, to: screen.visibleFrame), display: true)
        saveSize()
        if isHidden { toggleVisibility() }
        panel.orderFrontRegardless(); savePosition()
    }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) {
        detail.close(); detailDismissal = nil
        savePosition(); globeView.setRunning(false); weather.setActive(false); vessels.setActive(false)
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0); NotificationCenter.default.removeObserver($0); DistributedNotificationCenter.default().removeObserver($0) }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if isHidden { toggleVisibility() } else { resetPosition() }; return true
    }
    func windowDidMove(_ notification: Notification) { savePosition() }

    private func saveSize() {
        guard panel != nil else { return }
        globeSize = panel.frame.width/1.5
        defaults.set(Double(globeSize), forKey:"globeSize")
    }

    private func savePosition() {
        guard panel != nil else { return }
        defaults.set(NSStringFromPoint(panel.frame.origin), forKey: "origin")
    }
    private func restorePosition() {
        if let saved = defaults.string(forKey: "origin") {
            let point = NSPointFromString(saved)
            if point.x.isFinite && point.y.isFinite { panel.setFrameOrigin(point) }
            keepVisible()
        } else { resetPosition() }
    }
    private func keepVisible() {
        guard let screen = NSScreen.screens.max(by: {
            let a = $0.visibleFrame.intersection(panel.frame), b = $1.visibleFrame.intersection(panel.frame)
            return (a.isNull ? 0 : a.width*a.height) < (b.isNull ? 0 : b.width*b.height)
        }) else { return }
        panel.setFrame(GlobeSizing.fitting(panel.frame, to: screen.visibleFrame), display: true)
        saveSize()
    }
    private func updateRunning() {
        let running = !isHidden && !sleeping && !screenSleeping && !locked
        globeView.setRunning(running); weather.setActive(running); vessels.setActive(running)
        if running { weatherChanged() } else { detail.close() }
    }
    @objc private func refreshWeather() { weather.refresh(force:true) }
    @objc private func openWeatherSource() { NSWorkspace.shared.open(URL(string:"https://open-meteo.com/")!) }
    private func weatherChanged() {
        let visible = weather.inventory.usable(at:Date())
        if visible != renderedWeather {
            renderedWeather = visible
            globeView.globe.applyWeather(visible)
        }
        buildMenu()
        updateSelectedCard()
    }
    private func vesselsChanged() {
        if vessels.visible != renderedVessels {
            renderedVessels = vessels.visible
            globeView.globe.applyVessels(renderedVessels)
        }
        buildMenu(); updateSelectedCard()
    }
    private func updateSelectedCard() {
        guard detail.isShown else { return }
        if let id = selectedVesselID {
            guard let sample = vessels.sample(mmsi:id) else { detail.close(); return }
            detailContent.update(vesselCard(sample))
        } else if let coordinate = selectedCoordinate { detailContent.update(placeCard(at:coordinate)) }
    }
    private func vesselCard(_ sample: VesselSample) -> PlaceCard {
        let local = placeCard(at:sample.coordinate)
        return VesselCard.make(sample,language:language,weather:local.weather,weatherDetails:local.weatherDetails)
    }
    private func showVessel(_ id: String, at point: NSPoint) {
        if detail.isShown { detail.performClose(nil); return }
        guard let sample = vessels.sample(mmsi:id) else { return }
        selectedVesselID = id; selectedCoordinate = nil
        detailContent.update(vesselCard(sample),reset:true)
        detail.show(relativeTo:NSRect(x:point.x,y:point.y,width:1,height:1),of:globeView,preferredEdge:.maxY)
    }
    @objc private func configureVessels() {
        detail.close()
        let alert = NSAlert()
        alert.messageText = strings.text(.shipsSetupTitle)
        alert.informativeText = strings.text(.shipsSetupBody)
        let field = NSSecureTextField(frame:NSRect(x:0,y:0,width:330,height:24))
        field.placeholderString = "AISStream API Key"
        alert.accessoryView = field
        for label in [UIString.shipsSave,.cancel,.shipsAccount,.shipsRemove,.shipsRetrySaved] { alert.addButton(withTitle:strings.text(label)) }
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps:true)
        let response = alert.runModal()
        do {
            if response == .alertFirstButtonReturn {
                let key = field.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)
                field.stringValue = ""
                guard !key.isEmpty else { return }
                guard key.count <= 512, !key.contains(where: { $0.isWhitespace || $0.isNewline }) else { throw VesselKeychain.StorageError.unavailable }
                try VesselKeychain.save(key); vessels.reload()
            } else if response.rawValue == NSApplication.ModalResponse.alertFirstButtonReturn.rawValue+2 {
                NSWorkspace.shared.open(URL(string:"https://aisstream.io/account")!)
            } else if response.rawValue == NSApplication.ModalResponse.alertFirstButtonReturn.rawValue+3 {
                try VesselKeychain.remove(); vessels.reload()
            } else if response.rawValue == NSApplication.ModalResponse.alertFirstButtonReturn.rawValue+4 {
                vessels.authorizeSavedKey()
            }
        } catch {
            let failure = NSAlert(); failure.messageText = strings.text(.shipsKeyError)
            failure.informativeText = strings.text(.shipsKeyErrorBody); failure.runModal()
        }
        field.stringValue = ""
    }
    private func showWeather(at coordinate: GeoCoordinate, point: NSPoint) {
        if detail.isShown { detail.performClose(nil); return }
        selectedCoordinate = coordinate
        detailContent.update(placeCard(at:coordinate),reset:true)
        detail.show(relativeTo:NSRect(x:point.x,y:point.y,width:1,height:1),of:globeView,preferredEdge:.maxY)
    }
    private func placeCard(at coordinate: GeoCoordinate) -> PlaceCard {
        let date = Date()
        let place = atlas?.place(at:coordinate)
        let story = place.flatMap { cultures?.story(placeID:$0.id,at:coordinate,date:date) }
        let sea = place == nil ? marine?.region(at:coordinate):nil
        let fish = sea == nil ? nil:marine?.story(at:coordinate)
        let text = story?.text(in:language) ?? fish?.entry.text(in:language)
        let day = strings.text(coordinate.distance(to:SolarPosition.coordinate(at:date)) < 90 ? .day:.night)
        let compactWeather: String
        if let sample = weather.inventory.nearest(to:coordinate,at:date) {
            let older = date.timeIntervalSince(sample.validAt) > 5400 ? strings.text(.olderSuffix):""
            compactWeather = strings.format(.compactWeather,day,sample.temperature,sample.description(in:language))+older
        } else { compactWeather = strings.format(.compactUnavailable,day) }
        let unavailable = atlas == nil || cultures == nil
        return PlaceCard(
            language:language,
            region:sea?.name(in:language) ?? text?.regionLabel ?? place?.name(in:language) ?? coordinate.label,
            theme:text?.theme ?? strings.text(sea == nil ? .wandering:.marineTheme),
            title:text?.title ?? strings.text(sea != nil ? .marineMissingTitle:unavailable ? .cultureUnavailable:place == nil ? .oceanTitle:.missingStoryTitle),
            body:text?.body ?? strings.text(sea != nil ? .marineMissingBody:unavailable ? .cultureUnavailableBody:place == nil ? .oceanBody:.missingStoryBody),
            weather:compactWeather,weatherDetails:detailText(at:coordinate),
            sourceName:text?.sourceName,sourceURL:(story?.sourceURL ?? fish?.entry.sourceURL).flatMap { URL(string:$0) })
    }
    private func detailText(at coordinate: GeoCoordinate) -> String {
        let date = Date(), sun = SolarPosition.coordinate(at:Date())
        let day = strings.text(coordinate.distance(to:sun) < 90 ? .day:.night)
        let heading = "\(coordinate.label) · \(day)"
        guard let sample = weather.inventory.nearest(to:coordinate,at:date) else {
            return heading + "\n\n" + strings.text(.weatherMissingDetails)
        }
        let time = strings.date(sample.validAt)
        let age = date.timeIntervalSince(sample.validAt) > 5400 ? strings.text(.olderSuffix):""
        return heading + "\n\n" + strings.format(.weatherMeasurements,sample.temperature,sample.description(in:language),sample.cloudCover,sample.rainMMPerHour,sample.snowCMPerHour)
            + "\n\n" + strings.format(.weatherProvenance,time,age,sample.coordinate.label)
    }
    private func updatePointerPassthrough() {
        guard !globeView.rotation.isDragging else { panel.ignoresMouseEvents = false; return }
        let p = panel.mouseLocationOutsideOfEventStream
        panel.ignoresMouseEvents = !globeView.isInteractive(p)
    }
    private func observeLifecycle() {
        let center = NSWorkspace.shared.notificationCenter
        let mappings: [(Notification.Name,@MainActor (CompanionController)->Void)] = [
            (NSWorkspace.willSleepNotification, { $0.sleeping = true }),
            (NSWorkspace.didWakeNotification, { $0.sleeping = false }),
            (NSWorkspace.screensDidSleepNotification, { $0.screenSleeping = true }),
            (NSWorkspace.screensDidWakeNotification, { $0.screenSleeping = false })
        ]
        for (name, update) in mappings {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in guard let self else { return }; update(self); self.updateRunning() }
            })
        }
        for (name, value) in [("com.apple.screenIsLocked",true),("com.apple.screenIsUnlocked",false)] {
            observers.append(DistributedNotificationCenter.default().addObserver(forName: .init(name), object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.locked = value; self?.updateRunning() }
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.globeView.finishDrag()
                self?.detail.close()
                self?.keepVisible(); self?.buildMenu()
            }
        })
    }
}
