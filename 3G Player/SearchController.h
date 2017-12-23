//
//  SearchController.h
//  3G Player
//
//  Created by Admin on 10/24/15.
//  Copyright (c) 2015 themylogin. All rights reserved.
//

#import "ItemsListController.h"

@interface SearchController : ItemsListController

- (id)initWithPlayer:(NSDictionary*)player libraryDirectory:(NSString*)libraryDirectory;

- (void)loadSearchIndex;

- (void)search:(NSString*)query;

- (BOOL)update;

@end
