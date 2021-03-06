//
//  InfoController.m
//  3G Player
//
//  Created by Admin on 5/11/14.
//  Copyright (c) 2014 themylogin. All rights reserved.
//

#import "InfoController.h"

#import "Globals.h"

@interface InfoController ()

@property (nonatomic, retain) NSArray* statistics;
@property (nonatomic, retain) NSArray* candidatesForDeletion;

@end

@implementation InfoController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self)
    {
        self.tabBarItem.title = NSLocalizedString(@"Info", NIL);
        self.tabBarItem.image = [UIImage imageNamed:@"Info.png"];
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    CGRect tableViewRect = self.tableView.frame;
    tableViewRect.size.height = [UIScreen mainScreen].bounds.size.height - 68;
    self.tableView.frame = tableViewRect;
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(updateStatistics)
                                                 name:@"statisticsChanged"
                                               object:controllers.current];
    [self updateStatistics];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(updateCandidatesForDeletion)
                                                 name:@"historyUpdated"
                                               object:musicFileManager];
    [self updateCandidatesForDeletion];
}

- (void)viewDidLayoutSubviews
{    
    if (floor(NSFoundationVersionNumber) > NSFoundationVersionNumber_iOS_6_1)
    {
        self.navigationController.navigationBar.barStyle = UIBarStyleBlackOpaque;
        if ([self respondsToSelector:@selector(edgesForExtendedLayout)])
        {
            self.edgesForExtendedLayout = UIRectEdgeNone;
        }
        CGRect viewBounds = self.view.bounds;
        CGFloat topBarOffset = self.topLayoutGuide.length;
        viewBounds.origin.y = topBarOffset * -1;
        self.view.bounds = viewBounds;
        self.navigationController.navigationBar.translucent = NO;
    }
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (section == 0)
    {
        return [self.statistics count];
    }
    
    if (section == 1)
    {
        return [self.candidatesForDeletion count];
    }
    
    return 0;
}

- (NSString*)tableView:(UITableView*)tableView titleForHeaderInSection:(NSInteger)section
{
    if (section == 0)
    {
        return @"Statistics";
    }
    
    if (section == 1)
    {
        return @"Candidates for deletion";
    }
    
    return @"";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString* cellIdentifier = @"Cell";
    
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier];
    if (cell == nil)
    {
        cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellIdentifier] autorelease];
        cell.textLabel.adjustsFontSizeToFitWidth = true;
    }
    
    if (indexPath.section == 0)
    {
        cell.textLabel.text = [self.statistics objectAtIndex:indexPath.row];
    }
    if (indexPath.section == 1)
    {
        cell.textLabel.text = [musicFileManager navigationPathForItem:
                               [self.candidatesForDeletion objectAtIndex:indexPath.row]];
    }
    
    return cell;
}

#pragma mark - Table view delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath)
    {
        if (indexPath.section == 1)
        {
            NSDictionary* item = [self.candidatesForDeletion objectAtIndex:indexPath.row];
            [controllers.library navigateToItem:item enter:NO];
        }
    }
}

#pragma mark - Gesture recognizers

- (IBAction)handleLongPress:(UILongPressGestureRecognizer*)recognizer
{
    if (recognizer.state != UIGestureRecognizerStateBegan)
    {
        return;
    }
    
    NSIndexPath* indexPath = [self.tableView indexPathForRowAtPoint:[recognizer locationInView:self.tableView]];
    if (indexPath)
    {
        if (indexPath.section == 1)
        {
            [musicTableService showActionSheetForItem:[self.candidatesForDeletion objectAtIndex:indexPath.row]
                                               inView:self.view
                                     withExtraButtons:BlacklistExtraButton];
        }
    }
}

#pragma mark -

- (void)updateStatistics
{
    self.statistics = [controllers.current getStatistics];
    [self.tableView reloadData];
}

- (void)updateCandidatesForDeletion
{
    self.candidatesForDeletion = [musicFileManager listOldDirectories];
    [self.tableView reloadData];
}

@end
