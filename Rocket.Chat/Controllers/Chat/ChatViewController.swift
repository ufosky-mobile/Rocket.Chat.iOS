//
//  ChatViewController.swift
//  Rocket.Chat
//
//  Created by Rafael K. Streit on 7/21/16.
//  Copyright © 2016 Rocket.Chat. All rights reserved.
//

import SideMenu
import RealmSwift
import SlackTextViewController
import SafariServices
import MobilePlayer

class ChatViewController: SLKTextViewController {
    
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
    weak var chatTitleView: ChatTitleView?
    weak var chatPreviewModeView: ChatPreviewModeView?
    
    var searchResult: [String: Any] = [:]
    
    var messagesToken: NotificationToken!
    var messages: Results<Message>!
    var subscription: Subscription! {
        didSet {
            updateSubscriptionInfo()
            markAsRead()
        }
    }
    
    
    // MARK: View Life Cycle
    
    class func sharedInstance() -> ChatViewController? {
        if let nav = UIApplication.shared.delegate?.window??.rootViewController as? UINavigationController {
            return nav.viewControllers.first as? ChatViewController
        }
        
        return nil
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        navigationController?.navigationBar.isTranslucent = false
        navigationController?.navigationBar.barTintColor = UIColor.white
        navigationController?.navigationBar.tintColor = UIColor(rgb: 0x5B5B5B, alphaVal: 1)

        isInverted = false
        bounces = true
        shakeToClearEnabled = true
        isKeyboardPanningEnabled = true
        shouldScrollToBottomAfterKeyboardShows = false
        
        setupTitleView()
        setupSideMenu()
        registerCells()
        setupTextViewSettings()
    }
    
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        
        let insets = UIEdgeInsets(
            top: 0,
            left: 0,
            bottom: chatPreviewModeView?.frame.height ?? 0,
            right: 0
        )
        
        collectionView?.contentInset = insets
        collectionView?.scrollIndicatorInsets = insets
    }
    
    fileprivate func setupTextViewSettings() {
        textInputbar.autoHideRightButton = true

        textView.registerMarkdownFormattingSymbol("*", withTitle: "Bold")
        textView.registerMarkdownFormattingSymbol("_", withTitle: "Italic")
        textView.registerMarkdownFormattingSymbol("~", withTitle: "Strike")
        textView.registerMarkdownFormattingSymbol("`", withTitle: "Code")
        textView.registerMarkdownFormattingSymbol("```", withTitle: "Preformatted")
        textView.registerMarkdownFormattingSymbol(">", withTitle: "Quote")
        
        registerPrefixes(forAutoCompletion: ["@", "#"])
    }
    
    fileprivate func setupTitleView() {
        // FIXME: Use typealias or associatedType in the protocol, to avoid casting
        let view = ChatTitleView.instanceFromNib() as? ChatTitleView
        self.navigationItem.titleView = view
        chatTitleView = view
    }
    
    override class func collectionViewLayout(for decoder: NSCoder) -> UICollectionViewLayout {
        return UICollectionViewFlowLayout()
    }
    
    fileprivate func registerCells() {
        collectionView?.register(UINib(
            nibName: "ChatMessageCell",
            bundle: Bundle.main
        ), forCellWithReuseIdentifier: ChatMessageCell.identifier)
        
        autoCompletionView.register(UINib(
            nibName: "AutocompleteCell",
            bundle: Bundle.main
        ), forCellReuseIdentifier: AutocompleteCell.identifier)
    }
    
    fileprivate func scrollToBottom(_ animated: Bool = false) {
        let totalItems = collectionView!.numberOfItems(inSection: 0) - 1
        
        if totalItems > 0 {
            let indexPath = IndexPath(row: totalItems, section: 0)
            collectionView?.scrollToItem(at: indexPath, at: .bottom, animated: animated)
        }
    }
    
    
    // MARK: SlackTextViewController
    
    override func didPressRightButton(_ sender: Any?) {
        sendMessage()
    }
    
    override func didPressReturnKey(_ keyCommand: UIKeyCommand?) {
        sendMessage()
    }
    
    override func textViewDidBeginEditing(_ textView: UITextView) {
        scrollToBottom()
    }
    
    override func didChangeAutoCompletionPrefix(_ prefix: String, andWord word: String) {
        searchResult = [:]
        
        if prefix == "@" && word.characters.count > 0 {
            guard let users = try? Realm().objects(User.self).filter(NSPredicate(format: "username BEGINSWITH[c] %@", word)) else { return }

            for user in users {
                if let username = user.username {
                    searchResult[username] = user
                }
            }
            
            if "here".contains(word) {
                searchResult["here"] = UIImage(named: "Hashtag")
            }
            
            if "all".contains(word) {
                searchResult["all"] = UIImage(named: "Hashtag")
            }

        } else if prefix == "#" && word.characters.count > 0 {
            guard let channels = try? Realm().objects(Subscription.self).filter("auth != nil && (privateType == 'c' || privateType == 'p') && name BEGINSWITH[c] %@", word) else { return }
            
            for channel in channels {
                searchResult[channel.name] = channel.type == .channel ? UIImage(named: "Hashtag") : UIImage(named: "Lock")
            }

        }
        
        let show = (searchResult.count > 0)
        showAutoCompletionView(show)
    }
    
    override func heightForAutoCompletionView() -> CGFloat {
        return AutocompleteCell.minimumHeight * CGFloat(searchResult.count)
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return searchResult.keys.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        return autoCompletionCellForRowAtIndexPath(indexPath)
    }
    
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return AutocompleteCell.minimumHeight
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let key = Array(searchResult.keys)[indexPath.row]
        acceptAutoCompletion(with: "\(key) ", keepPrefix: true)
    }
    
    func autoCompletionCellForRowAtIndexPath(_ indexPath: IndexPath) -> AutocompleteCell {
        let key = Array(searchResult.keys)[indexPath.row]
        let cell = autoCompletionView.dequeueReusableCell(withIdentifier: AutocompleteCell.identifier) as! AutocompleteCell
        cell.selectionStyle = .default
        
        if let user = searchResult[key] as? User {
            cell.avatarView.isHidden = false
            cell.imageViewIcon.isHidden = true
            cell.avatarView.user = user
        } else {
            cell.avatarView.isHidden = true
            cell.imageViewIcon.isHidden = false
            
            if let image = searchResult[key] as? UIImage {
                cell.imageViewIcon.image = image.imageWithTint(.lightGray)
            }
        }

        cell.labelTitle.text = key
        return cell
    }
    
    
    // MARK: Message
    
    fileprivate func sendMessage() {
        guard let message = textView.text else { return }
        
        SubscriptionManager.sendTextMessage(message, subscription: subscription) { [unowned self] (response) in
            self.textView.text = ""
        }
    }
    
    
    // MARK: Subscription
    
    fileprivate func markAsRead() {
        SubscriptionManager.markAsRead(subscription) { (response) in
            // Nothing, for now
        }
    }
    
    fileprivate func updateSubscriptionInfo() {
        if let token = messagesToken {
            token.stop()
        }

        activityIndicator.startAnimating()
        title = subscription?.name
        chatTitleView?.subscription = subscription
        
        if subscription.isValid() {
            updateSubscriptionMessages()
        } else {
            subscription.fetchRoomIdentifier({ [unowned self] (response) in
                self.subscription = response
            })
        }
        
        if self.subscription.isJoined() {
            setTextInputbarHidden(false, animated: false)
            chatPreviewModeView?.removeFromSuperview()
        } else {
            setTextInputbarHidden(true, animated: false)
            showChatPreviewModeView()
        }
    }
    
    fileprivate func updateSubscriptionMessages() {
        messages = subscription?.messages.sorted(byProperty: "createdAt", ascending: true)
        messagesToken = messages.addNotificationBlock { [unowned self] (changes) in
            if self.messages.count > 0 {
                self.activityIndicator.stopAnimating()
            }
            
            self.collectionView?.reloadData()
            self.collectionView?.layoutIfNeeded()
            self.scrollToBottom()
        }
        
        MessageManager.getHistory(subscription) { [unowned self] (response) in
            self.activityIndicator.stopAnimating()
            self.messages = self.subscription?.fetchMessages()
            self.collectionView?.reloadData()
            self.collectionView?.layoutIfNeeded()
            self.scrollToBottom()
        }
        
        MessageManager.changes(subscription)
    }
    
    fileprivate func showChatPreviewModeView() {
        chatPreviewModeView?.removeFromSuperview()

        let previewView = ChatPreviewModeView.instanceFromNib() as! ChatPreviewModeView
        previewView.delegate = self
        previewView.subscription = subscription
        previewView.frame = CGRect(x: 0, y: view.frame.height - previewView.frame.height, width: view.frame.width, height: previewView.frame.height)
        view.addSubview(previewView)
        chatPreviewModeView = previewView
    }
    
    
    // MARK: IBAction
    
    @IBAction func buttonMenuDidPressed(_ sender: AnyObject) {
        present(SideMenuManager.menuLeftNavigationController!, animated: true, completion: nil)
    }
    
    
    // MARK: Side Menu
    
    fileprivate func setupSideMenu() {
        let storyboardSubscriptions = UIStoryboard(name: "Subscriptions", bundle: Bundle.main)
        SideMenuManager.menuFadeStatusBar = false
        SideMenuManager.menuLeftNavigationController = storyboardSubscriptions.instantiateInitialViewController() as? UISideMenuNavigationController
        
        SideMenuManager.menuAddPanGestureToPresent(toView: self.navigationController!.navigationBar)
        SideMenuManager.menuAddScreenEdgePanGesturesToPresent(toView: self.navigationController!.view)
    }
    
}


// MARK: UICollectionViewDataSource

extension ChatViewController {
    
    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return messages?.count ?? 0
    }
    
    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: ChatMessageCell.identifier,
            for: indexPath
        ) as! ChatMessageCell

        cell.delegate = self
        
        if messages?.count ?? 0 > indexPath.row {
            let message = messages![indexPath.row]
            cell.message = message
        }

        return cell
    }
    
}


extension ChatViewController: UICollectionViewDelegateFlowLayout {
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
        return .zero
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let message = messages![indexPath.row]
        let fullWidth = UIScreen.main.bounds.size.width
        let height = ChatMessageCell.cellMediaHeightFor(message: message)
        return CGSize(width: fullWidth, height: height)
    }
    
}


// MARK: ChatPreviewModeViewProtocol

extension ChatViewController: ChatPreviewModeViewProtocol {
    
    func userDidJoinedSubscription() {
        guard let auth = AuthManager.isAuthenticated() else { return }
        guard let subscription = self.subscription else { return }
        
        Realm.execute { (realm) in
            subscription.auth = auth
        }
        
        self.subscription = subscription
    }
    
}


// MARK: ChatURLCellProtocol

extension ChatViewController: ChatMessageCellProtocol {
    
    func openURL(url: URL) {
        let controller = SFSafariViewController(url: url)
        present(controller, animated: true, completion: nil)
    }
    
    func openURLFromCell(url: MessageURL) {
        guard let targetURL = url.targetURL else { return }
        guard let destinyURL = URL(string: targetURL) else { return }
        let controller = SFSafariViewController(url: destinyURL)
        present(controller, animated: true, completion: nil)
    }
    
    func openVideoFromCell(attachment: Attachment) {
        guard let videoURL = attachment.fullVideoURL() else { return }
        let controller = MobilePlayerViewController(contentURL: videoURL)
        controller.title = attachment.title
        controller.activityItems = [attachment.title, videoURL]
        present(controller, animated: true, completion: nil)
    }

}
