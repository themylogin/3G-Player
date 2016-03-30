//
//  RecentsController.m
//  3G Player
//
//  Created by Admin on 12/4/14.
//  Copyright (c) 2014 themylogin. All rights reserved.
//

#import "RecentsController.h"

#import "Globals.h"

@interface RecentsController () <UIBarPositioningDelegate>

@end

@implementation RecentsController

- (id)init
{
    self = [super init];
    if (self)
    {
        self.tabBarItem.title = NSLocalizedString(@"Recents", NIL);
        self.tabBarItem.image = [UIImage imageNamed:@"Recents"];
        
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
                                                 name:@"historyUpdated"
                                               object:musicFileManager];
    [self updateRecents];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)updateRecents
{
    [self setItems:[musicFileManager listRecentItems]];
}

#pragma mark — Navbar positioning

- (UIBarPosition)positionForBar:(id<UIBarPositioning>)bar
{
    return UIBarPositionTopAttached;
}

#pragma mark - Internals

- (void)onMusicFileManagerStateChanged
{
    [self.tableView reloadData];
}

@end
