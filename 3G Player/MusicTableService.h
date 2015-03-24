//
//  MusicTableService.h
//  3G Player
//
//  Created by Admin on 12/4/14.
//  Copyright (c) 2014 themylogin. All rights reserved.
//

#import <Foundation/Foundation.h>

#import <UIKit/UIKit.h>

#import "CurrentController.h"

@interface MusicTableService : NSObject <UIActionSheetDelegate>

typedef enum { BlacklistExtraButton } ExtraButtons;

- (id)init;

- (UITableViewCell*)cellForMusicItem:(NSDictionary*)item tableView:(UITableView *)tableView;
- (void)showActionSheetForItem:(NSDictionary*)item inView:(UIView*)view withExtraButtons:(int)extraButtons;

- (void)addItemToPlaylist:(NSDictionary*)item mode:(AddMode)addMode playAfter:(BOOL)playAfter;
- (NSMutableArray*)readRecentsFile;

- (NSArray*)loadIndexFor:(NSString*)path;
- (BOOL)isDirectory:(NSDictionary*)item;
- (BOOL)isBlacklisted:(NSDictionary*)item;
- (void)blacklistItem:(NSDictionary*)item;
- (void)unblacklistItem:(NSDictionary*)item;
- (BOOL)isBuffered:(NSDictionary*)item;

@end
