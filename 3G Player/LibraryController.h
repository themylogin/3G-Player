//
//  LibraryController.h
//  3G Player
//
//  Created by Admin on 7/2/13.
//  Copyright (c) 2013 themylogin. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface LibraryController : UINavigationController

- (id)initWithRoot;

- (void)updateLibrary;
- (void)updateLibraryWithSuccessCallback:(void(^)())callback;

@end
