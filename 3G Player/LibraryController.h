//
//  LibraryController.h
//  3G Player
//
//  Created by Admin on 7/2/13.
//  Copyright (c) 2013 themylogin. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface LibraryController : UINavigationController <UIActionSheetDelegate, UISearchBarDelegate>

@property (nonatomic, retain) UISearchBar* librarySearchBar;

- (id)initWithPlayer:(NSDictionary*)player;

- (void)changePlayer:(NSDictionary*)player;

- (void)updateLibrary;
- (void)updateLibraryWithSuccessCallback:(void(^)())callback;

- (void)navigateToItem:(NSDictionary*)item enter:(BOOL)enter;

@end
