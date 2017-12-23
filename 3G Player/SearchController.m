//
//  SearchController.m
//  3G Player
//
//  Created by Admin on 10/24/15.
//  Copyright (c) 2015 themylogin. All rights reserved.
//

#import "SearchController.h"

#import "AppDelegate.h"
#import "Globals.h"
#import "LibraryPageController.h"

@interface SearchController () <UIBarPositioningDelegate>

@property (nonatomic, retain) NSDictionary* player;
@property (nonatomic, retain) NSString* libraryDirectory;

@property (nonatomic, retain) NSArray* searchIndex;

@property (nonatomic, retain) NSString* query;

@end

@implementation SearchController

- (id)initWithPlayer:(NSDictionary*)player libraryDirectory:(NSString*)libraryDirectory;
{
    self = [super init];
    
    if (self)
    {
        self.player = player;
        self.libraryDirectory = libraryDirectory;
        
        [self loadSearchIndex];
        
        self.query = nil;
    }
    
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.navigationItem.rightBarButtonItem = libraryRightBarButtonItem;
    self.toolbarItems = [NSArray arrayWithObject:libraryToolbarButtonItem];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    controllers.library.librarySearchBar.text = self.title;
    [controllers.library.librarySearchBar becomeFirstResponder];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)loadSearchIndex
{
    NSString* searchJsonPath = [self.libraryDirectory stringByAppendingString:@"/search.json"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:searchJsonPath])
    {
        self.searchIndex = [NSJSONSerialization
                            JSONObjectWithData:[NSData dataWithContentsOfFile:searchJsonPath]
                            options:0
                            error:nil];
    }
    else
    {
        self.searchIndex = [NSArray array];
    }
}

- (void)search:(NSString*)query;
{
    NSString* searchText = query;
    searchText = [searchText lowercaseString];
    searchText = [searchText stringByReplacingOccurrencesOfString:@" " withString:@""];
    
    NSMutableArray* results = [NSMutableArray arrayWithCapacity:100];
    if (![searchText isEqualToString:@""])
    {
        for (int i = 0; i < self.searchIndex.count; i++)
        {
            if ([self.searchIndex[i][@"key"] hasPrefix:searchText])
            {
                NSMutableDictionary* item = [self.searchIndex[i][@"item"] mutableCopy];
                item[@"player"] = self.player;
                [results addObject:item];
                if (results.count == 100)
                {
                    break;
                }
            }
        }
    }
    
    self.query = query;
    
    self.title = query;
    [self setItems:results];
}

- (BOOL)update
{
    if (self.query)
    {
        [self search:self.query];
    }
    
    return TRUE;
}

#pragma mark — Navbar positioning

- (UIBarPosition)positionForBar:(id<UIBarPositioning>)bar
{
    return UIBarPositionTopAttached;
}

@end
