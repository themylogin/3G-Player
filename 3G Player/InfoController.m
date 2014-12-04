//
//  InfoController.m
//  3G Player
//
//  Created by Admin on 5/11/14.
//  Copyright (c) 2014 themylogin. All rights reserved.
//

#import "InfoController.h"

#import "Globals.h"

#import "JSONKit.h"

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
    
    NSMutableArray* readableCandidates = [NSMutableArray array];
    for (int i = 0; i < [candidates count]; i++)
    {
        NSString* candidate = [candidates objectAtIndex:i];
        NSArray* parts = [candidate componentsSeparatedByString:@"/"];
        NSMutableArray* readableCandidate = [NSMutableArray array];
        for (int j = 0; j < [parts count]; j++)
        {
            NSString* indexJsonPath = [[[libraryDirectory stringByAppendingString:@"/"] stringByAppendingString:[[parts subarrayWithRange:NSMakeRange(0, j)] componentsJoinedByString:@"/"]] stringByAppendingString:@"/index.json"];
            NSDictionary* index = [[JSONDecoder decoder] objectWithData:[NSData dataWithContentsOfFile:indexJsonPath]];
            NSDictionary* readableCandidatePart = nil;
            NSString* readableCandidatePartPath = [[parts subarrayWithRange:NSMakeRange(0, j + 1)] componentsJoinedByString:@"/"];
            for (NSString* key in index)
            {
                NSDictionary* probableReadableCandidatePart = [index objectForKey:key];
                if ([[probableReadableCandidatePart objectForKey:@"path"] isEqualToString:readableCandidatePartPath])
                {
                    readableCandidatePart = probableReadableCandidatePart;
                }
            }
            if (readableCandidatePart)
            {
                [readableCandidate addObject:[readableCandidatePart objectForKey:@"name"]];
            }
            else
            {
                [readableCandidate addObject:@"..."];
            }
        }
        [readableCandidates addObject:[readableCandidate componentsJoinedByString:@"/"]];
    }
    
    self.candidatesForDeletion.numberOfLines = 0;
    self.candidatesForDeletion.text = [readableCandidates componentsJoinedByString:@"\n"];
    
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
