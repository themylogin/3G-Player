//
//  RecommendationsForFromResultController.m
//  3G Player
//
//  Created by themylogin on 30/03/16.
//  Copyright © 2016 themylogin. All rights reserved.
//

#import "RecommendationsForFromResultController.h"

#import "AppDelegate.h"
#import "Globals.h"
#import "LibraryPageController.h"

@interface RecommendationsForFromResultController () <UIBarPositioningDelegate>

@end

@implementation RecommendationsForFromResultController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.navigationItem.rightBarButtonItem = libraryRightBarButtonItem;
    self.toolbarItems = [NSArray arrayWithObject:libraryToolbarButtonItem];
}

- (void)addItem:(NSDictionary *)item
{
    [self setItems:[self.items arrayByAddingObject:item]];
}

#pragma mark — Navbar positioning

- (UIBarPosition)positionForBar:(id<UIBarPositioning>)bar
{
    return UIBarPositionTopAttached;
}

@end
