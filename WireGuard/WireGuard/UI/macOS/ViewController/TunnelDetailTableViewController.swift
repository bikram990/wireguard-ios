// SPDX-License-Identifier: MIT
// Copyright © 2018-2019 WireGuard LLC. All Rights Reserved.

import Cocoa

class TunnelDetailTableViewController: NSViewController {

    private enum TableViewModelRow {
        case interfaceFieldRow(TunnelViewModel.InterfaceField)
        case peerFieldRow(peer: TunnelViewModel.PeerData, field: TunnelViewModel.PeerField)
        case onDemandRow
        case spacerRow

        func localizedSectionKeyString() -> String {
            switch self {
            case .interfaceFieldRow: return tr("tunnelSectionTitleInterface")
            case .peerFieldRow: return tr("tunnelSectionTitlePeer")
            case .onDemandRow: return ""
            case .spacerRow: return ""
            }
        }

        func isTitleRow() -> Bool {
            switch self {
            case .interfaceFieldRow(let field): return field == .name
            case .peerFieldRow(_, let field): return field == .publicKey
            case .onDemandRow: return true
            case .spacerRow: return false
            }
        }
    }

    let interfaceFields: [TunnelViewModel.InterfaceField] = [
        .name, .publicKey, .addresses,
        .listenPort, .mtu, .dns
    ]

    let peerFields: [TunnelViewModel.PeerField] = [
        .publicKey, .preSharedKey, .endpoint,
        .allowedIPs, .persistentKeepAlive,
        .rxBytes, .txBytes, .lastHandshakeTime
    ]

    let tableView: NSTableView = {
        let tableView = NSTableView()
        tableView.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("TunnelDetail")))
        tableView.headerView = nil
        tableView.rowSizeStyle = .medium
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .none
        return tableView
    }()

    let statusCheckbox: NSButton = {
        let checkbox = NSButton()
        checkbox.title = ""
        checkbox.setButtonType(.switch)
        checkbox.state = .off
        checkbox.toolTip = "Toggle status (⌘T)"
        return checkbox
    }()

    let editButton: NSButton = {
        let button = NSButton()
        button.title = tr("Edit")
        button.setButtonType(.momentaryPushIn)
        button.bezelStyle = .rounded
        button.toolTip = "Edit tunnel (⌘E)"
        return button
    }()

    let box: NSBox = {
        let box = NSBox()
        box.titlePosition = .noTitle
        box.fillColor = .unemphasizedSelectedContentBackgroundColor
        return box
    }()

    let tunnelsManager: TunnelsManager
    let tunnel: TunnelContainer
    var tunnelViewModel: TunnelViewModel {
        didSet {
            updateTableViewModelRows()
        }
    }
    private var tableViewModelRows = [TableViewModelRow]()
    private var statusObservationToken: AnyObject?
    private var tunnelEditVC: TunnelEditViewController?

    init(tunnelsManager: TunnelsManager, tunnel: TunnelContainer) {
        self.tunnelsManager = tunnelsManager
        self.tunnel = tunnel
        tunnelViewModel = TunnelViewModel(tunnelConfiguration: tunnel.tunnelConfiguration)
        super.init(nibName: nil, bundle: nil)
        updateTableViewModelRows()
        updateStatus()
        statusObservationToken = tunnel.observe(\TunnelContainer.status) { [weak self] _, _ in
            self?.updateStatus()
        }

        // TODO(roopc): call reloadRuntimeConfiguration() once per second
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        tableView.dataSource = self
        tableView.delegate = self

        statusCheckbox.target = self
        statusCheckbox.action = #selector(statusCheckboxToggled(sender:))

        editButton.target = self
        editButton.action = #selector(handleEditTunnelAction)

        let clipView = NSClipView()
        clipView.documentView = tableView

        let scrollView = NSScrollView()
        scrollView.contentView = clipView // Set contentView before setting drawsBackground
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let containerView = NSView()
        let bottomControlsContainer = NSLayoutGuide()
        containerView.addLayoutGuide(bottomControlsContainer)
        containerView.addSubview(box)
        containerView.addSubview(scrollView)
        containerView.addSubview(statusCheckbox)
        containerView.addSubview(editButton)
        box.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        statusCheckbox.translatesAutoresizingMaskIntoConstraints = false
        editButton.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            containerView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            containerView.leadingAnchor.constraint(equalTo: bottomControlsContainer.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: bottomControlsContainer.trailingAnchor),
            bottomControlsContainer.heightAnchor.constraint(equalToConstant: 32),
            scrollView.bottomAnchor.constraint(equalTo: bottomControlsContainer.topAnchor),
            bottomControlsContainer.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            statusCheckbox.leadingAnchor.constraint(equalTo: bottomControlsContainer.leadingAnchor),
            bottomControlsContainer.bottomAnchor.constraint(equalTo: statusCheckbox.bottomAnchor, constant: 4),
            editButton.trailingAnchor.constraint(equalTo: bottomControlsContainer.trailingAnchor),
            bottomControlsContainer.bottomAnchor.constraint(equalTo: editButton.bottomAnchor, constant: 4)
        ])

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: box.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: box.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: box.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: box.trailingAnchor)
        ])

        view = containerView
    }

    func updateTableViewModelRows() {
        tableViewModelRows = []
        for field in interfaceFields where !tunnelViewModel.interfaceData[field].isEmpty {
            tableViewModelRows.append(.interfaceFieldRow(field))
        }
        for peerData in tunnelViewModel.peersData {
            tableViewModelRows.append(.spacerRow)
            for field in peerFields where !peerData[field].isEmpty {
                tableViewModelRows.append(.peerFieldRow(peer: peerData, field: field))
            }
        }
        tableViewModelRows.append(.spacerRow)
        tableViewModelRows.append(.onDemandRow)
    }

    func updateStatus() {
        let statusText: String
        switch tunnel.status {
        case .waiting:
            statusText = tr("tunnelStatusWaiting")
        case .inactive:
            statusText = tr("tunnelStatusInactive")
        case .activating:
            statusText = tr("tunnelStatusActivating")
        case .active:
            statusText = tr("tunnelStatusActive")
        case .deactivating:
            statusText = tr("tunnelStatusDeactivating")
        case .reasserting:
            statusText = tr("tunnelStatusReasserting")
        case .restarting:
            statusText = tr("tunnelStatusRestarting")
        }
        statusCheckbox.title = tr(format: "macStatus (%@)", statusText)
        let shouldBeChecked = (tunnel.status != .inactive && tunnel.status != .deactivating)
        let shouldBeEnabled = (tunnel.status == .active || tunnel.status == .inactive)
        statusCheckbox.state = shouldBeChecked ? .on : .off
        statusCheckbox.isEnabled = shouldBeEnabled
        reloadRuntimeConfiguration()
    }

    @objc func handleEditTunnelAction() {
        let tunnelEditVC = TunnelEditViewController(tunnelsManager: tunnelsManager, tunnel: tunnel)
        tunnelEditVC.delegate = self
        presentAsSheet(tunnelEditVC)
        self.tunnelEditVC = tunnelEditVC
    }

    @objc func handleToggleActiveStatusAction() {
        if tunnel.status == .inactive {
            tunnelsManager.startActivation(of: tunnel)
        } else if tunnel.status == .active {
            tunnelsManager.startDeactivation(of: tunnel)
        }
    }

    @objc func statusCheckboxToggled(sender: AnyObject?) {
        guard let statusCheckbox = sender as? NSButton else { return }
        if statusCheckbox.state == .on {
            tunnelsManager.startActivation(of: tunnel)
        } else if statusCheckbox.state == .off {
            tunnelsManager.startDeactivation(of: tunnel)
        }
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        if let tunnelEditVC = tunnelEditVC {
            dismiss(tunnelEditVC)
        }
    }

    private func reloadRuntimeConfiguration() {
        tunnel.getRuntimeTunnelConfiguration(completionHandler: {
            guard let tunnelConfiguration = $0 else { return }
            if tunnelConfiguration == self.tunnel.tunnelConfiguration {
                return
            }
            self.tunnelViewModel = TunnelViewModel(tunnelConfiguration: tunnelConfiguration)
            // TODO(roopc): make this not loose scroll position
            self.tableView.reloadData()
            self.tunnelEditVC = nil
        })
    }
}

extension TunnelDetailTableViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return tableViewModelRows.count
    }
}

extension TunnelDetailTableViewController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let modelRow = tableViewModelRows[row]
        switch modelRow {
        case .interfaceFieldRow(let field):
            let cell: KeyValueRow = tableView.dequeueReusableCell()
            let localizedKeyString = modelRow.isTitleRow() ? modelRow.localizedSectionKeyString() : field.localizedUIString
            cell.key = tr(format: "macFieldKey (%@)", localizedKeyString)
            cell.value = tunnelViewModel.interfaceData[field]
            cell.isKeyInBold = modelRow.isTitleRow()
            return cell
        case .peerFieldRow(let peerData, let field):
            let cell: KeyValueRow = tableView.dequeueReusableCell()
            let localizedKeyString = modelRow.isTitleRow() ? modelRow.localizedSectionKeyString() : field.localizedUIString
            cell.key = tr(format: "macFieldKey (%@)", localizedKeyString)
            cell.value = peerData[field]
            cell.isKeyInBold = modelRow.isTitleRow()
            return cell
        case .spacerRow:
            return NSView()
        case .onDemandRow:
            let cell: KeyValueRow = tableView.dequeueReusableCell()
            cell.key = tr("macFieldOnDemand")
            cell.value = TunnelViewModel.activateOnDemandDetailText(for: tunnel.activateOnDemandSetting)
            cell.isKeyInBold = true
            return cell
        }
    }
}

extension TunnelDetailTableViewController: TunnelEditViewControllerDelegate {
    func tunnelSaved(tunnel: TunnelContainer) {
        tunnelViewModel = TunnelViewModel(tunnelConfiguration: tunnel.tunnelConfiguration)
        tableView.reloadData()
        self.tunnelEditVC = nil
        updateStatus()
    }

    func tunnelEditingCancelled() {
        self.tunnelEditVC = nil
    }
}
