import AppKit
import WindowCore

private final class OverviewPanel: NSPanel {
    override func cancelOperation(_ sender: Any?) { close() }
}

final class WindowOverview: NSObject, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private let catalog = AccessibleWindows()
    private var panel: NSPanel?
    private let search = NSSearchField()
    private let table = NSTableView()
    private let status = NSTextField(wrappingLabelWithString: "")
    private let empty = NSTextField(wrappingLabelWithString: "")
    private let permission = NSButton(title: "Разрешить Универсальный доступ…", target: nil, action: nil)
    private let openButton = NSButton(title: "Открыть окно", target: nil, action: nil)
    private var entries: [WindowEntry] = []
    private var filtered: [WindowEntry] = []
    private var timer: Timer?
    private var scanning = false
    private var activating = false
    private var lastSnapshot: WindowSnapshot?

    func show() {
        if panel == nil { buildPanel() }
        panel?.makeKeyAndOrderFront(nil)
        if #available(macOS 14.0, *) { NSApp.activate() }
        else { NSApp.activate(ignoringOtherApps: true) }
        panel?.makeFirstResponder(search)
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.refresh() }
    }

    private func buildPanel() {
        let panel = OverviewPanel(contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
                            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        panel.title = "ScreenDock Experimental — Все окна"
        panel.minSize = NSSize(width: 580, height: 360)
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.delegate = self
        panel.center()
        self.panel = panel

        let heading = NSTextField(labelWithString: "Найдите нужное окно")
        heading.font = .systemFont(ofSize: 23, weight: .semibold)
        let subtitle = NSTextField(wrappingLabelWithString: "Окна всех рабочих столов, включая свёрнутые. Вкладки внутри браузера в список не входят.")
        subtitle.textColor = .secondaryLabelColor
        search.placeholderString = "Название документа или приложение"
        search.delegate = self
        search.sendsSearchStringImmediately = true
        search.setAccessibilityLabel("Поиск окон")

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("window"))
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 62
        table.intercellSpacing = NSSize(width: 0, height: 2)
        table.usesAlternatingRowBackgroundColors = true
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(openSelected)
        table.setAccessibilityLabel("Открытые окна")
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        empty.alignment = .center
        empty.textColor = .secondaryLabelColor
        let list = NSView()
        for view in [scroll, empty] {
            list.addSubview(view)
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: list.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: list.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: list.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: list.bottomAnchor),
            empty.centerXAnchor.constraint(equalTo: list.centerXAnchor),
            empty.centerYAnchor.constraint(equalTo: list.centerYAnchor),
            empty.widthAnchor.constraint(lessThanOrEqualTo: list.widthAnchor, constant: -48)
        ])

        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        permission.target = self
        permission.action = #selector(openPermissionSettings)
        permission.isHidden = true
        openButton.target = self
        openButton.action = #selector(openSelected)
        openButton.keyEquivalent = "\r"
        let refresh = NSButton(title: "Обновить", target: self, action: #selector(manualRefresh))
        let quit = NSButton(title: "Выход", target: self, action: #selector(quit))
        let buttons = NSStackView(views: [refresh, permission, NSView(), quit, openButton])
        buttons.spacing = 10
        let hint = NSTextField(labelWithString: "Введите название → ↑↓ → Enter. Или дважды нажмите на строку. Esc — закрыть.")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.lineBreakMode = .byTruncatingTail
        let stack = NSStackView(views: [heading, subtitle, search, list, status, hint, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        guard let content = panel.contentView else { return }
        content.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        for view in [subtitle, search, list, status, hint, buttons] {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
            search.heightAnchor.constraint(equalToConstant: 30),
            list.heightAnchor.constraint(greaterThanOrEqualToConstant: 90)
        ])
        list.setContentHuggingPriority(.defaultLow, for: .vertical)
        list.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
    }

    @objc private func manualRefresh() { refresh() }

    private func refresh() {
        guard panel?.isVisible == true, !scanning, !activating else { return }
        scanning = true
        status.stringValue = "Обновляю список…"
        if entries.isEmpty { empty.stringValue = "Ищу открытые окна…"; empty.isHidden = false }
        catalog.refresh { [weak self] snapshot in
            guard let self else { return }
            self.scanning = false
            self.entries = snapshot.entries
            self.lastSnapshot = snapshot
            self.permission.isHidden = !snapshot.needsPermission
            self.updateList()
        }
    }

    private var selectedID: WindowID? {
        filtered.indices.contains(table.selectedRow) ? filtered[table.selectedRow].id : nil
    }

    private func updateList() {
        let previous = selectedID
        filtered = WindowIndex.search(entries, query: search.stringValue)
        table.reloadData()
        if let selected = WindowIndex.selection(previous: previous, in: filtered),
           let row = filtered.firstIndex(where: { $0.id == selected }) {
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        } else { table.deselectAll(nil) }
        openButton.isEnabled = !filtered.isEmpty && !activating
        empty.isHidden = !filtered.isEmpty
        if lastSnapshot?.needsPermission == true {
            empty.stringValue = "Разрешите «Универсальный доступ», чтобы увидеть окна всех приложений.\nЗатем вернитесь сюда и нажмите «Обновить»."
            status.stringValue = "Нужно разрешение. Запись экрана не требуется."
        } else {
            empty.stringValue = search.stringValue.isEmpty ? "Открытых окон не найдено." : "Ничего не найдено. Попробуйте другое название."
            let unavailable = lastSnapshot?.unavailableApps ?? 0
            status.stringValue = "Окон: \(filtered.count) из \(entries.count)" +
                (unavailable > 0 ? " · Не ответили приложения: \(unavailable). Список может быть неполным." : " · Все рабочие столы")
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { filtered.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard filtered.indices.contains(row) else { return nil }
        let entry = filtered[row]
        let cell = NSTableCellView()
        let icon = NSImageView()
        icon.image = NSRunningApplication(processIdentifier: entry.id.pid)?.icon
        icon.imageScaling = .scaleProportionallyUpOrDown
        let title = NSTextField(labelWithString: entry.title)
        title.font = .systemFont(ofSize: 13, weight: .medium)
        title.lineBreakMode = .byTruncatingMiddle
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        var details = [entry.appName]
        if entry.isMinimized { details.append("Свёрнуто") }
        if entry.isHidden { details.append("Приложение скрыто") }
        if entry.isFullScreen { details.append("На весь экран") }
        let app = NSTextField(labelWithString: details.joined(separator: " · "))
        app.font = .systemFont(ofSize: 11)
        app.textColor = .secondaryLabelColor
        app.lineBreakMode = .byTruncatingTail
        let labels = NSStackView(views: [title, app])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 4
        for view in [icon, labels] {
            cell.addSubview(view)
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 10),
            icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 34),
            icon.heightAnchor.constraint(equalToConstant: 34),
            labels.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12),
            labels.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -12),
            labels.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            title.widthAnchor.constraint(equalTo: labels.widthAnchor),
            app.widthAnchor.constraint(equalTo: labels.widthAnchor)
        ])
        cell.textField = title
        cell.imageView = icon
        cell.toolTip = entry.appName + " — " + entry.title
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        openButton.isEnabled = selectedID != nil && !activating
    }

    func controlTextDidChange(_ notification: Notification) { updateList() }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy command: Selector) -> Bool {
        if command == #selector(NSResponder.insertNewline(_:)) { openSelected(); return true }
        if command == #selector(NSResponder.cancelOperation(_:)) { panel?.close(); return true }
        if command == #selector(NSResponder.moveDown(_:)) || command == #selector(NSResponder.moveUp(_:)) {
            guard !filtered.isEmpty else { return true }
            let offset = command == #selector(NSResponder.moveDown(_:)) ? 1 : -1
            let row = max(0, min(filtered.count - 1, table.selectedRow + offset))
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            table.scrollRowToVisible(row)
            return true
        }
        return false
    }

    @objc private func openSelected() {
        guard let id = selectedID, !activating else { return }
        activating = true
        openButton.isEnabled = false
        status.stringValue = "Открываю окно…"
        catalog.activate(id) { [weak self] result in
            guard let self else { return }
            self.activating = false
            if result == .focused { self.panel?.close() }
            else {
                self.openButton.isEnabled = self.selectedID != nil
                self.status.stringValue = result == .windowGone || result == .appUnavailable
                    ? "Окно уже закрыто или приложение недоступно. Нажмите «Обновить»."
                    : "Не удалось открыть окно. Проверьте «Универсальный доступ» и попробуйте снова."
            }
        }
    }

    @objc private func openPermissionSettings() {
        Permissions.ensureAccessibility()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }
    func windowWillClose(_ notification: Notification) { timer?.invalidate(); timer = nil }

    #if DEBUG
    /// The live check renders only its own fixture titles, never user documents.
    func renderPreview(entries: [WindowEntry], to url: URL) throws {
        if panel == nil { buildPanel() }
        self.entries = entries
        lastSnapshot = WindowSnapshot(entries: entries, needsPermission: false, unavailableApps: 0)
        updateList()
        panel?.orderFront(nil)
        guard let content = panel?.contentView else { throw NSError(domain: "Preview", code: 1) }
        content.layoutSubtreeIfNeeded()
        content.displayIfNeeded()
        panel?.displayIfNeeded()
        guard let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) else {
            throw NSError(domain: "Preview", code: 2)
        }
        content.cacheDisplay(in: content.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "Preview", code: 3)
        }
        try png.write(to: url)
        panel?.close()
    }
    #endif
}
