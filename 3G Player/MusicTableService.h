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

typedef enum { BlacklistExtraButton = 1 } ExtraButtons;

- (id)init;

- (NSDictionary*)loadRawIndexForPlayer:(NSDictionary*)player directory:(NSString*)directory;
- (NSArray*)loadIndexForPlayer:(NSDictionary*)player directory:(NSString*)directory;
- (NSArray*)loadIndexForItem:(NSDictionary*)item;
- (NSDictionary*)annotateItem:(NSDictionary*)item withPlayer:(NSDictionary*)player;

- (UITableViewCell*)cellForMusicItem:(NSDictionary*)item tableView:(UITableView *)tableView;
- (UITableViewCell*)cellForMusicItem:(NSDictionary*)item tableView:(UITableView *)tableView showFullPath:(bool)showFullPath;
- (void)showActionSheetForItem:(NSDictionary*)item inView:(UIView*)view withExtraButtons:(int)extraButtons;

- (void)addItemToPlaylist:(NSDictionary*)item mode:(AddMode)addMode playAfter:(BOOL)playAfter;

- (BOOL)isDirectory:(NSDictionary*)item;

- (BOOL)isBlacklisted:(NSDictionary*)item;
- (void)blacklistItem:(NSDictionary*)item;
- (void)unblacklistItem:(NSDictionary*)item;

- (BOOL)isBuffered:(NSDictionary*)item;

@end
