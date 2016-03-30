//
//  RecommendationsUtils.h
//  3G Player
//
//  Created by themylogin on 30/03/16.
//  Copyright © 2016 themylogin. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef enum {
    RecommendationsAddToPlaylist,
    RecommendationsShowInController,
} RecommendationsAction;

@interface RecommendationsUtils : NSObject

- (id)init;

- (void)processRecommendationsUrl:(NSURL*)url withPlayer:(NSDictionary*)player title:(NSString*)title action:(RecommendationsAction)action;

@end
