//
//  RecommendationsUtils.m
//  3G Player
//
//  Created by themylogin on 30/03/16.
//  Copyright © 2016 themylogin. All rights reserved.
//

#import "RecommendationsUtils.h"

#import "ASIHTTPRequest.h"
#import "JSONKit.h"

#import "Globals.h"
#import "RecommendationsForFromResultController.h"

@interface RecommendationsUtils ()

@property (nonatomic, retain) ASIHTTPRequest* request;

@end

@implementation RecommendationsUtils

- (id)init
{
    self.request = nil;
    return self;
}

- (void)processRecommendationsUrl:(NSURL*)url withPlayer:(NSDictionary*)player title:(NSString*)title action:(RecommendationsAction)action
{
    RecommendationsForFromResultController* resultController = nil;
    if (action == RecommendationsShowInController)
    {
        resultController = [[RecommendationsForFromResultController alloc] init];
        resultController.title = title;
        
        [controllers.library pushViewController:resultController animated:YES];
        [resultController release];
        
        [controllers.tabBar setSelectedViewController:controllers.library];
    }
    
    self.request = [ASIHTTPRequest requestWithURL:url];
    [self.request setAllowCompressedResponse:NO];
    [self.request setShouldContinueWhenAppEntersBackground:YES];
    [self.request setDataReceivedBlock:^(NSData* data){
        NSArray* results = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]
                            componentsSeparatedByString:@"\n"];
        for (int i = 0; i < results.count; i++)
        {
            NSString* result = [results objectAtIndex:i];
            NSDictionary* item = [[JSONDecoder decoder] objectWithData:[result dataUsingEncoding:NSUTF8StringEncoding]];
            if (item)
            {
                item = [musicTableService annotateItem:item withPlayer:player];
                
                if (action == RecommendationsShowInController)
                {
                    [resultController addItem:item];
                }
                if (action == RecommendationsAddToPlaylist)
                {
                    [controllers.current addFiles:[NSArray arrayWithObject:item] mode:AddToTheEnd];
                }
            }
        }
    }];
    [self.request setCompletionBlock:^{
    }];
    [self.request startAsynchronous];
}

@end
