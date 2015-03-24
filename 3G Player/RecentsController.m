//
//  RecentsController.m
//  3G Player
//
//  Created by Admin on 12/4/14.
//  Copyright (c) 2014 themylogin. All rights reserved.
//

#import "RecentsController.h"

#import "AppDelegate.h"
#import "Globals.h"
#import "LibraryPageController.h"

@interface RecentsController () <UIBarPositioningDelegate>

@property (nonatomic, retain) NSArray* recents;
@property (nonatomic, retain) IBOutlet UITableView *tableView;

@end

@implementation RecentsController

- (id)init
{
    self = [super init];
    if (self)
    {
        self.tabBarItem.title = NSLocalizedString(@"Recents", NIL);
        self.tabBarItem.image = [UIImage imageNamed:@"tabbar_recents.png"];
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(onMusicFileManagerStateChanged)
                                                     name:@"stateChanged"
                                                   object:musicFileManager];
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.edgesForExtendedLayout = UIRectEdgeNone;
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(updateRecents)
                                                 name:@"recentsUpdated"
                                               object:musicTableService];
    [self updateRecents];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)updateRecents
{
    self.recents = [musicTableService readRecentsFile];
    [self.tableView reloadData];
}

#pragma mark — navbar positioning

- (UIBarPosition)positionForBar:(id<UIBarPositioning>)bar
{
    return UIBarPositionTopAttached;
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return [self.recents count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSDictionary* item = [self getItemForIndexPath:indexPath];
    return [musicTableService cellForMusicItem:item tableView:tableView];
}

#pragma mark - Table view delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSDictionary* item = [self getItemForIndexPath:indexPath];
    
    NSMutableArray* libraryControllers = [[NSMutableArray alloc] init];
    NSMutableArray* scrollTargets = [[NSMutableArray alloc] init];
    NSString* parent = [item objectForKey:@"path"];
    NSDictionary* child = item;
    while (![(parent = [parent stringByDeletingLastPathComponent]) isEqualToString:@""])
    {
        NSDictionary* parentItem = [musicFileManager itemByPath:parent];
        if (parentItem != nil)
        {
            LibraryPageController* controller = [[LibraryPageController alloc]
                                                 initWithDirectory:parent
                                                 title:[parentItem objectForKey:@"name"]];
            [libraryControllers insertObject:controller atIndex:0];
            [scrollTargets insertObject:child atIndex:0];
            child = parentItem;
            
        }
    }
    
    [controllers.library popToRootViewControllerAnimated:NO];
    for (int i = 0; i < [libraryControllers count]; i++)
    {
        [controllers.library pushViewController:[libraryControllers objectAtIndex:i] animated:NO];
    }
    AppDelegate* delegate = (AppDelegate*)[[UIApplication sharedApplication] delegate];
    [delegate.tabBarController setSelectedViewController:controllers.library];
    dispatch_async(dispatch_get_main_queue(), ^{
        for (int i = 0; i < [libraryControllers count]; i++)
        {
            [[libraryControllers objectAtIndex:i] scrollToItem:[scrollTargets objectAtIndex:i]];
        }
    });
}

#pragma mark - Gesture recognizer

- (IBAction)handleSwipe:(UISwipeGestureRecognizer*)recognizer
{
    NSIndexPath* indexPath = [self.tableView indexPathForRowAtPoint:[recognizer locationInView:self.tableView]];
    if (indexPath)
    {
        NSDictionary* item = [self getItemForIndexPath:indexPath];
        [musicTableService addItemToPlaylist:item mode:AddToTheEnd playAfter:NO];
    }
}

- (IBAction)handleLongPress:(UILongPressGestureRecognizer*)recognizer
{
    if (recognizer.state != UIGestureRecognizerStateBegan)
    {
        return;
    }
    
    NSIndexPath* indexPath = [self.tableView indexPathForRowAtPoint:[recognizer locationInView:self.tableView]];
    if (indexPath)
    {
        NSDictionary* item = [self getItemForIndexPath:indexPath];        
        [musicTableService showActionSheetForItem:item
                                           inView:self.view
                                 withExtraButtons:BlacklistExtraButton];
    }
}

- (NSDictionary*)getItemForIndexPath:(NSIndexPath*)indexPath
{
    return [self.recents objectAtIndex:indexPath.row];
}

- (void)onMusicFileManagerStateChanged
{
    [self.tableView reloadData];
}

@end
