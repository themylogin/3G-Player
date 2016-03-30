//
//  ItemsListController.h
//  3G Player
//
//  Created by Admin on 3/30/16.
//  Copyright (c) 2016 themylogin. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface ItemsListController : UIViewController

@property (nonatomic, retain) IBOutlet UITableView *tableView;

@property (nonatomic, retain) NSArray* items;

@end
