//
//  AppDelegate.h
//  3G Player
//
//  Created by Admin on 7/2/13.
//  Copyright (c) 2013 themylogin. All rights reserved.
//

#import <HockeySDK/HockeySDK.h>
#import <UIKit/UIKit.h>

@interface AppDelegate : UIResponder <UIApplicationDelegate, BITCrashManagerDelegate>

@property (strong, nonatomic) UIWindow *window;

@property (nonatomic, retain) UITabBarController* tabBarController;

@end
