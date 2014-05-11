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

@end

@implementation InfoController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self)
    {
        self.tabBarItem.title = NSLocalizedString(@"Info", NIL);
        self.tabBarItem.image = [UIImage imageNamed:@"tabbar_info.png"];
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateCandidatesForDeletion) name:@"oldDirectoriesUpdated" object:musicFileManager];
    [self updateCandidatesForDeletion];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)updateCandidatesForDeletion
{
    NSArray* old = [musicFileManager listOldDirectories];
    NSArray* candidates = [old subarrayWithRange:NSMakeRange(0, MIN([old count], 5))];
    
    self.candidatesForDeletion.numberOfLines = 0;
    self.candidatesForDeletion.text = [candidates componentsJoinedByString:@"\n"];
    
    CGRect currentFrame = self.candidatesForDeletion.frame;
    CGSize max = CGSizeMake(self.candidatesForDeletion.frame.size.width, 1024);
    CGSize expected = [self.candidatesForDeletion.text sizeWithFont:self.candidatesForDeletion.font constrainedToSize:max lineBreakMode:self.candidatesForDeletion.lineBreakMode];
    currentFrame.size.height = expected.height;
    self.candidatesForDeletion.frame = currentFrame;
    
    if ([candidates count] > 0)
    {
        self.candidatesForDeletionHeader.hidden = NO;
        self.candidatesForDeletion.hidden = NO;
    }
    else
    {
        self.candidatesForDeletionHeader.hidden = YES;
        self.candidatesForDeletion.hidden = YES;
    }
    
    [self.view layoutIfNeeded];
}

@end
