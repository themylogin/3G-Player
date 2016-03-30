//
//  SearchController.m
//  3G Player
//
//  Created by Admin on 10/24/15.
//  Copyright (c) 2015 themylogin. All rights reserved.
//

#import "SearchController.h"

#import "AppDelegate.h"
#import "Globals.h"
#import "LibraryPageController.h"

@interface SearchController () <UIBarPositioningDelegate>

@end

@implementation SearchController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.navigationItem.rightBarButtonItem = libraryRightBarButtonItem;
    self.toolbarItems = [NSArray arrayWithObject:libraryToolbarButtonItem];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    controllers.library.librarySearchBar.text = self.title;
    [controllers.library.librarySearchBar becomeFirstResponder];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)setSearchQuery:(NSString*)query results:(NSArray*)results;
{
    self.title = query;
    [self setItems:results];
}

#pragma mark — Navbar positioning

- (UIBarPosition)positionForBar:(id<UIBarPositioning>)bar
{
    return UIBarPositionTopAttached;
}

@end
