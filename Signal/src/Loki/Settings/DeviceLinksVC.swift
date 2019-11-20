
// MARK: - Device Links View Controller

@objc(LKDeviceLinksVC)
final class DeviceLinksVC : UIViewController, UITableViewDataSource, UITableViewDelegate, DeviceLinkingModalDelegate, DeviceNameModalDelegate {
    private var deviceLinks: [DeviceLink] = [] { didSet { updateUI() } }
    
    // MARK: Components
    private lazy var tableView: UITableView = {
        let result = UITableView()
        result.dataSource = self
        result.delegate = self
        result.register(Cell.self, forCellReuseIdentifier: "Cell")
        result.separatorStyle = .none
        result.backgroundColor = .clear
        return result
    }()
    
    private lazy var callToActionView : UIStackView = {
        let explanationLabel = UILabel()
        explanationLabel.textColor = Theme.primaryColor
        explanationLabel.font = UIFont.ows_dynamicTypeSubheadlineClamped
        explanationLabel.numberOfLines = 0
        explanationLabel.lineBreakMode = .byWordWrapping
        explanationLabel.textAlignment = .center
        explanationLabel.text = NSLocalizedString("You don't have any linked devices yet", comment: "")
        let linkNewDeviceButtonFont = UIFont.ows_dynamicTypeBodyClamped.ows_mediumWeight()
        let linkNewDeviceButtonHeight = linkNewDeviceButtonFont.pointSize * 48 / 17
        let linkNewDeviceButton = OWSFlatButton.button(title: NSLocalizedString("Link a Device", comment: ""), font: linkNewDeviceButtonFont, titleColor: .lokiGreen(), backgroundColor: .clear, target: self, selector: #selector(linkNewDevice))
        linkNewDeviceButton.setBackgroundColors(upColor: .clear, downColor: .clear)
        linkNewDeviceButton.autoSetDimension(.height, toSize: linkNewDeviceButtonHeight)
        linkNewDeviceButton.button.contentHorizontalAlignment = .left
        let result = UIStackView(arrangedSubviews: [ explanationLabel, linkNewDeviceButton ])
        result.axis = .vertical
        result.spacing = 4
        result.alignment = .center
        return result
    }()
    
    // MARK: Lifecycle
    override func viewDidLoad() {
        title = NSLocalizedString("Linked Devices", comment: "")
        let masterDeviceHexEncodedPublicKey = UserDefaults.standard.string(forKey: "masterDeviceHexEncodedPublicKey")
        let isMasterDevice = (masterDeviceHexEncodedPublicKey == nil)
        if isMasterDevice {
            navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(linkNewDevice))
        }
        view.backgroundColor = Theme.backgroundColor
        view.addSubview(tableView)
        tableView.pin(to: view)
        view.addSubview(callToActionView)
        callToActionView.center(in: view)
        updateDeviceLinks()
    }
    
    // MARK: Data
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return deviceLinks.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell") as! Cell
        let deviceLink = deviceLinks[indexPath.row]
        cell.deviceLink = deviceLink
        return cell
    }
    
    // MARK: Updating
    private func updateDeviceLinks() {
        let storage = OWSPrimaryStorage.shared()
        let userHexEncodedPublicKey = OWSIdentityManager.shared().identityKeyPair()!.hexEncodedPublicKey
        var deviceLinks: [DeviceLink] = []
        storage.dbReadConnection.read { transaction in
            deviceLinks = storage.getDeviceLinks(for: userHexEncodedPublicKey, in: transaction).sorted { lhs, rhs in
                return lhs.other.hexEncodedPublicKey > rhs.other.hexEncodedPublicKey
            }
        }
        self.deviceLinks = deviceLinks
    }
    
    private func updateUI() {
        tableView.reloadData()
        UIView.animate(withDuration: 0.25) {
            self.callToActionView.isHidden = !self.deviceLinks.isEmpty
        }
    }
    
    func handleDeviceLinkAuthorized(_ deviceLink: DeviceLink) {
        updateDeviceLinks()
    }
    
    func handleDeviceLinkingModalDismissed() {
        // Do nothing
    }
    
    // MARK: Interaction
    @objc private func linkNewDevice() {
        if deviceLinks.isEmpty {
            let deviceLinkingModal = DeviceLinkingModal(mode: .master, delegate: nil)
            deviceLinkingModal.modalPresentationStyle = .overFullScreen
            present(deviceLinkingModal, animated: true, completion: nil)
        } else {
            let alert = UIAlertController(title: NSLocalizedString("Multi Device Limit Reached", comment: ""), message: NSLocalizedString("It's currently not allowed to link more than one device.", comment: ""), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default, handler: nil))
            present(alert, animated: true, completion: nil)
        }
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let deviceLink = deviceLinks[indexPath.row]
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: NSLocalizedString("Change Name", comment: ""), style: .default) { [weak self] _ in
            guard let self = self else { return }
            let deviceNameModal = DeviceNameModal()
            deviceNameModal.deviceLink = deviceLink
            deviceNameModal.delegate = self
            self.present(deviceNameModal, animated: true, completion: nil)
        })
        sheet.addAction(UIAlertAction(title: NSLocalizedString("Unlink", comment: ""), style: .destructive) { _ in
            // TODO: Implement
        })
        present(sheet, animated: true, completion: nil)
    }
    
    @objc func handleDeviceNameChanged(to name: String, for device: DeviceLink.Device) {
        updateUI()
    }
}

// MARK: - Cell

private extension DeviceLinksVC {
    
    final class Cell : UITableViewCell {
        var deviceLink: DeviceLink! { didSet { update() } }
        
        // MARK: Components
        private lazy var titleLabel: UILabel = {
            let result = UILabel()
            result.textColor = Theme.primaryColor
            result.font = UIFont.ows_dynamicTypeSubheadlineClamped
            result.lineBreakMode = .byTruncatingTail
            return result
        }()
        
        private lazy var subtitleLabel: UILabel = {
            let result = UILabel()
            result.textColor = Theme.primaryColor
            result.font = UIFont.ows_dynamicTypeCaption1Clamped
            result.lineBreakMode = .byTruncatingTail
            return result
        }()
        
        // MARK: Initialization
        override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
            super.init(style: style, reuseIdentifier: reuseIdentifier)
            setUpViewHierarchy()
        }
        
        required init?(coder: NSCoder) {
            super.init(coder: coder)
            setUpViewHierarchy()
        }
        
        private func setUpViewHierarchy() {
            backgroundColor = .clear
            let stackView = UIStackView(arrangedSubviews: [ titleLabel, subtitleLabel ])
            stackView.axis = .vertical
            stackView.distribution = .equalCentering
            stackView.spacing = 4
            stackView.set(.height, to: 36)
            contentView.addSubview(stackView)
            stackView.pin(.leading, to: .leading, of: contentView, withInset: 16)
            stackView.pin(.top, to: .top, of: contentView, withInset: 8)
            contentView.pin(.trailing, to: .trailing, of: stackView, withInset: 16)
            contentView.pin(.bottom, to: .bottom, of: stackView, withInset: 8)
            stackView.set(.width, to: UIScreen.main.bounds.width - 2 * 16)
        }
        
        // MARK: Updating
        private func update() {
            if let displayName = deviceLink.displayName {
                titleLabel.text = displayName
                subtitleLabel.text = deviceLink.other.hexEncodedPublicKey
                subtitleLabel.isHidden = false
            } else {
                titleLabel.text = deviceLink.other.hexEncodedPublicKey
                subtitleLabel.isHidden = true
            }
        }
    }
}
