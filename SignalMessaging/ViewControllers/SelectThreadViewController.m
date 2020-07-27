//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "SelectThreadViewController.h"
#import "BlockListUIUtils.h"
#import "ContactTableViewCell.h"
#import "ContactsViewHelper.h"
#import "Environment.h"
#import "NewNonContactConversationViewController.h"
#import "OWSContactsManager.h"
#import "OWSSearchBar.h"
#import "OWSTableViewController.h"
#import "ThreadViewHelper.h"
#import "UIColor+OWS.h"
#import "UIFont+OWS.h"
#import "UIView+OWS.h"
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SessionServiceKit/NSString+SSK.h>
#import <SessionServiceKit/PhoneNumber.h>
#import <SessionServiceKit/SignalAccount.h>
#import <SessionServiceKit/TSAccountManager.h>
#import <SessionServiceKit/TSContactThread.h>
#import <SessionServiceKit/TSThread.h>
#import <YapDatabase/YapDatabase.h>

NS_ASSUME_NONNULL_BEGIN

@interface SelectThreadViewController () <OWSTableViewControllerDelegate,
    ThreadViewHelperDelegate,
    ContactsViewHelperDelegate,
    UISearchBarDelegate,
    NewNonContactConversationViewControllerDelegate>

@property (nonatomic, readonly) ContactsViewHelper *contactsViewHelper;
@property (nonatomic, readonly) FullTextSearcher *fullTextSearcher;
@property (nonatomic, readonly) ThreadViewHelper *threadViewHelper;
@property (nonatomic, readonly) YapDatabaseConnection *uiDatabaseConnection;

@property (nonatomic, readonly) OWSTableViewController *tableViewController;

@property (nonatomic, readonly) UISearchBar *searchBar;

@end

#pragma mark -

@implementation SelectThreadViewController

- (void)loadView
{
    [super loadView];

    UIBarButtonItem *closeButton = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"X"] style:UIBarButtonItemStylePlain target:self action:@selector(dismissPressed:)];
    closeButton.tintColor = LKColors.text;
    self.navigationItem.leftBarButtonItem = closeButton;
    
    _contactsViewHelper = [[ContactsViewHelper alloc] initWithDelegate:self];
    _fullTextSearcher = FullTextSearcher.shared;
    _threadViewHelper = [ThreadViewHelper new];
    _threadViewHelper.delegate = self;

    _uiDatabaseConnection = [[OWSPrimaryStorage sharedManager] newDatabaseConnection];
#ifdef DEBUG
    _uiDatabaseConnection.permittedTransactions = YDB_AnyReadTransaction;
#endif
    [_uiDatabaseConnection beginLongLivedReadTransaction];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(yapDatabaseModified:)
                                                 name:YapDatabaseModifiedNotification
                                               object:OWSPrimaryStorage.sharedManager.dbNotificationObject];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(yapDatabaseModifiedExternally:)
                                                 name:YapDatabaseModifiedExternallyNotification
                                               object:nil];

    [self createViews];
    
    // Loki: Set gradient background
    self.tableViewController.tableView.backgroundColor = UIColor.clearColor;
    self.tableViewController.view.backgroundColor = UIColor.clearColor;
    CAGradientLayer *layer = [CAGradientLayer new];
    layer.frame = UIScreen.mainScreen.bounds;
    layer.colors = @[ (id)[UIColor colorWithRGBHex:0x171717].CGColor, (id)[UIColor colorWithRGBHex:0x121212].CGColor ];
    [self.tableViewController.view.layer insertSublayer:layer atIndex:0];
    
    // Loki: Set navigation bar background color
    UINavigationBar *navigationBar = self.navigationController.navigationBar;
    [navigationBar setBackgroundImage:[UIImage new] forBarMetrics:UIBarMetricsDefault];
    navigationBar.shadowImage = [UIImage new];
    [navigationBar setTranslucent:NO];
    navigationBar.barTintColor = LKColors.navigationBarBackground;

    [self updateTableContents];
}

- (void)createViews
{
    OWSAssertDebug(self.selectThreadViewDelegate);

    // Search
    /*
    UISearchBar *searchBar = [OWSSearchBar new];
    _searchBar = searchBar;
    searchBar.delegate = self;
    searchBar.placeholder = NSLocalizedString(@"Search by public key", @"");
    [searchBar sizeToFit];

    UIView *header = [self.selectThreadViewDelegate createHeaderWithSearchBar:searchBar];
    if (!header) {
        header = searchBar;
    }
    [self.view addSubview:header];
    [header autoPinWidthToSuperview];
    [header autoPinEdge:ALEdgeTop toEdge:ALEdgeTop ofView:self.view withOffset:0.0f];
    [header setCompressionResistanceVerticalHigh];
    [header setContentHuggingVerticalHigh];
     */

    // Table
    _tableViewController = [OWSTableViewController new];
    _tableViewController.delegate = self;
    [self.view addSubview:self.tableViewController.view];
    [self.tableViewController.view autoPinEdgeToSuperviewSafeArea:ALEdgeLeading];
    [self.tableViewController.view autoPinEdgeToSuperviewSafeArea:ALEdgeTrailing];
    [_tableViewController.view autoPinEdgeToSuperviewEdge:ALEdgeTop];
    [_tableViewController.view autoPinEdgeToSuperviewEdge:ALEdgeBottom];
    self.tableViewController.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableViewController.tableView.estimatedRowHeight = 60;
}

- (void)yapDatabaseModifiedExternally:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    OWSLogVerbose(@"");

    [self.uiDatabaseConnection beginLongLivedReadTransaction];
    [self updateTableContents];
}

- (void)yapDatabaseModified:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();
    
    [self.uiDatabaseConnection beginLongLivedReadTransaction];
    [self updateTableContents];
}

#pragma mark - UISearchBarDelegate

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText
{
    [self updateTableContents];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar
{
    [self updateTableContents];
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar
{
    [self updateTableContents];
}

- (void)searchBarResultsListButtonClicked:(UISearchBar *)searchBar
{
    [self updateTableContents];
}

- (void)searchBar:(UISearchBar *)searchBar selectedScopeButtonIndexDidChange:(NSInteger)selectedScope
{
    [self updateTableContents];
}

#pragma mark - Table Contents

- (void)updateTableContents
{
    __weak SelectThreadViewController *weakSelf = self;
    ContactsViewHelper *helper = self.contactsViewHelper;
    OWSTableContents *contents = [OWSTableContents new];

    /*
    OWSTableSection *findByPhoneSection = [OWSTableSection new];
    [findByPhoneSection
        addItem:[OWSTableItem disclosureItemWithText:NSLocalizedString(@"NEW_CONVERSATION_FIND_BY_PHONE_NUMBER",
                                                         @"A label the cell that lets you add a new member to a group.")
                                     customRowHeight:UITableViewAutomaticDimension
                                         actionBlock:^{
                                             NewNonContactConversationViewController *viewController =
                                                 [NewNonContactConversationViewController new];
                                             viewController.nonContactConversationDelegate = weakSelf;
                                             viewController.isPresentedInNavigationController = YES;
                                             [weakSelf.navigationController pushViewController:viewController
                                                                                      animated:YES];
                                         }]];
    [contents addSection:findByPhoneSection];
     */

    // Existing threads are listed first, ordered by most recently active
    OWSTableSection *recentChatsSection = [OWSTableSection new];
    recentChatsSection.headerTitle = NSLocalizedString(@"SELECT_THREAD_TABLE_RECENT_CHATS_TITLE", @"");
    for (TSThread *thread in [self filteredThreadsWithSearchText]) {
        [recentChatsSection
            addItem:[OWSTableItem
                        itemWithCustomCellBlock:^{
                            SelectThreadViewController *strongSelf = weakSelf;
                            OWSCAssertDebug(strongSelf);

                            // To be consistent with the threads (above), we use ContactTableViewCell
                            // instead of HomeViewCell to present contacts and threads.
                            ContactTableViewCell *cell = [ContactTableViewCell new];

                            BOOL isBlocked = [helper isThreadBlocked:thread];
                            if (isBlocked) {
                                cell.accessoryMessage = NSLocalizedString(
                                    @"CONTACT_CELL_IS_BLOCKED", @"An indicator that a contact has been blocked.");
                            }

                            [cell configureWithThread:thread];

                            if (!cell.hasAccessoryText) {
                                // Don't add a disappearing messages indicator if we've already added a "blocked" label.
                                __block OWSDisappearingMessagesConfiguration *disappearingMessagesConfiguration;
                                [self.uiDatabaseConnection
                                    readWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
                                        disappearingMessagesConfiguration = [OWSDisappearingMessagesConfiguration
                                            fetchObjectWithUniqueID:thread.uniqueId
                                                        transaction:transaction];
                                    }];

                                if (disappearingMessagesConfiguration && disappearingMessagesConfiguration.isEnabled) {
                                    DisappearingTimerConfigurationView *disappearingTimerConfigurationView =
                                        [[DisappearingTimerConfigurationView alloc]
                                            initWithDurationSeconds:disappearingMessagesConfiguration.durationSeconds];

                                    disappearingTimerConfigurationView.tintColor = LKColors.text;
                                    [disappearingTimerConfigurationView autoSetDimensionsToSize:CGSizeMake(44, 44)];

                                    [cell ows_setAccessoryView:disappearingTimerConfigurationView];
                                }
                            }

                            return cell;
                        }
                        customRowHeight:UITableViewAutomaticDimension
                        actionBlock:^{
                            typeof(self) strongSelf = weakSelf;
                            if (!strongSelf) {
                                return;
                            }

                            BOOL isBlocked = [helper isThreadBlocked:thread];
                            if (isBlocked && ![strongSelf.selectThreadViewDelegate canSelectBlockedContact]) {
                                [BlockListUIUtils
                                    showUnblockThreadActionSheet:thread
                                              fromViewController:strongSelf
                                                 blockingManager:helper.blockingManager
                                                 contactsManager:helper.contactsManager
                                                 completionBlock:^(BOOL isStillBlocked) {
                                                     if (!isStillBlocked) {
                                                         [strongSelf.selectThreadViewDelegate threadWasSelected:thread];
                                                     }
                                                 }];
                                return;
                            }

                            [strongSelf.selectThreadViewDelegate threadWasSelected:thread];
                        }]];
    }

    if (recentChatsSection.itemCount > 0) {
        [contents addSection:recentChatsSection];
    }

    // Contacts who don't yet have a thread are listed last
    OWSTableSection *otherContactsSection = [OWSTableSection new];
    otherContactsSection.headerTitle = @"Other Chats";
    NSArray<SignalAccount *> *filteredSignalAccounts = [self filteredSignalAccountsWithSearchText];
    for (SignalAccount *signalAccount in filteredSignalAccounts) {
        [otherContactsSection
            addItem:[OWSTableItem
                        itemWithCustomCellBlock:^{
                            SelectThreadViewController *strongSelf = weakSelf;
                            OWSCAssertDebug(strongSelf);

                            ContactTableViewCell *cell = [ContactTableViewCell new];
                            BOOL isBlocked = [helper isRecipientIdBlocked:signalAccount.recipientId];
                            if (isBlocked) {
                                cell.accessoryMessage = NSLocalizedString(
                                    @"CONTACT_CELL_IS_BLOCKED", @"An indicator that a contact has been blocked.");
                            }
                            [cell configureWithRecipientId:signalAccount.recipientId];
                            return cell;
                        }
                        customRowHeight:UITableViewAutomaticDimension
                        actionBlock:^{
                            [weakSelf signalAccountWasSelected:signalAccount];
                        }]];
    }

    if (otherContactsSection.itemCount > 0) {
        [contents addSection:otherContactsSection];
    }

    if (recentChatsSection.itemCount + otherContactsSection.itemCount < 1) {
        OWSTableSection *emptySection = [OWSTableSection new];
        [emptySection
            addItem:[OWSTableItem
                        softCenterLabelItemWithText:NSLocalizedString(@"SETTINGS_BLOCK_LIST_NO_CONTACTS",
                                                        @"A label that indicates the user has no Signal contacts.")]];
        [contents addSection:emptySection];
    }

    self.tableViewController.contents = contents;
}

- (void)signalAccountWasSelected:(SignalAccount *)signalAccount
{
    OWSAssertDebug(signalAccount);
    OWSAssertDebug(self.selectThreadViewDelegate);

    ContactsViewHelper *helper = self.contactsViewHelper;

    if ([helper isRecipientIdBlocked:signalAccount.recipientId]
        && ![self.selectThreadViewDelegate canSelectBlockedContact]) {

        __weak SelectThreadViewController *weakSelf = self;
        [BlockListUIUtils showUnblockSignalAccountActionSheet:signalAccount
                                           fromViewController:self
                                              blockingManager:helper.blockingManager
                                              contactsManager:helper.contactsManager
                                              completionBlock:^(BOOL isBlocked) {
                                                  if (!isBlocked) {
                                                      [weakSelf signalAccountWasSelected:signalAccount];
                                                  }
                                              }];
        return;
    }

    __block TSThread *thread = nil;
    [LKStorage writeSyncWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        thread = [TSContactThread getOrCreateThreadWithContactId:signalAccount.recipientId transaction:transaction];
    } error:nil];
    OWSAssertDebug(thread);

    [self.selectThreadViewDelegate threadWasSelected:thread];
}

#pragma mark - Filter

- (NSArray<TSThread *> *)filteredThreadsWithSearchText
{
    return self.threadViewHelper.threads;
}

- (NSArray<SignalAccount *> *)filteredSignalAccountsWithSearchText
{
    // We don't want to show a 1:1 thread with Alice and Alice's contact,
    // so we de-duplicate by recipientId.
    NSArray<TSThread *> *threads = self.threadViewHelper.threads;
    NSMutableSet *contactIdsToIgnore = [NSMutableSet new];
    for (TSThread *thread in threads) {
        if ([thread isKindOfClass:[TSContactThread class]]) {
            TSContactThread *contactThread = (TSContactThread *)thread;
            [contactIdsToIgnore addObject:contactThread.contactIdentifier];
        }
    }

    NSString *searchString = self.searchBar.text;
    NSArray<SignalAccount *> *matchingAccounts =
        [self.contactsViewHelper signalAccountsMatchingSearchString:searchString];

    return [matchingAccounts
        filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(SignalAccount *signalAccount,
                                        NSDictionary<NSString *, id> *_Nullable bindings) {
            return ![contactIdsToIgnore containsObject:signalAccount.recipientId];
        }]];
}

#pragma mark - Events

- (void)dismissPressed:(id)sender
{
    [self.searchBar resignFirstResponder];
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - OWSTableViewControllerDelegate

- (void)tableViewWillBeginDragging
{
    [self.searchBar resignFirstResponder];
}

#pragma mark - ThreadViewHelperDelegate

- (void)threadListDidChange
{
    [self updateTableContents];
}

#pragma mark - ContactsViewHelperDelegate

- (void)contactsViewHelperDidUpdateContacts
{
    [self updateTableContents];
}

- (BOOL)shouldHideLocalNumber
{
    return NO;
}

#pragma mark - NewNonContactConversationViewControllerDelegate

- (void)recipientIdWasSelected:(NSString *)recipientId
{
    SignalAccount *signalAccount = [self.contactsViewHelper fetchOrBuildSignalAccountForRecipientId:recipientId];
    [self signalAccountWasSelected:signalAccount];
}

@end

NS_ASSUME_NONNULL_END
