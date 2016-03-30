//
//  SearchController.h
//  3G Player
//
//  Created by Admin on 10/24/15.
//  Copyright (c) 2015 themylogin. All rights reserved.
//

#import "ItemsListController.h"

@interface SearchController : ItemsListController

- (void)setSearchQuery:(NSString*)query results:(NSArray*)results;

@end
