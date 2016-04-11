//
//  RecommendationsForFromController.m
//  3G Player
//
//  Created by themylogin on 29/03/16.
//  Copyright © 2016 themylogin. All rights reserved.
//

#import "RecommendationsForFromController.h"

#import "Globals.h"

#import "ASIFormDataRequest.h"

@interface RecommendationsForFromController ()

@property (nonatomic, retain) NSDateFormatter* dateFormatter;

@property (nonatomic, retain) NSMutableArray* friends;
@property (nonatomic, retain) NSMutableDictionary* friendPlayer;

@end

@implementation RecommendationsForFromController

- (id)init
{
    self = [super init];
    if (self)
    {
        self.dateFormatter = [[NSDateFormatter alloc] init];
        self.dateFormatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        self.dateFormatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss";
        self.dateFormatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
        [self.dateFormatter release];
        
        self.friends = [NSMutableArray array];
        self.friendPlayer = [NSMutableDictionary dictionary];
        for (int i = 0; i < [players count]; i++)
        {
            NSDictionary* player = [players objectAtIndex:i];
            NSArray* lastFmUsernames = [player objectForKey:@"lastFmUsernames"];
            for (int j = 0; j < [lastFmUsernames count]; j++)
            {
                [self.friends addObject:[lastFmUsernames objectAtIndex:j]];
                [self.friendPlayer setObject:player forKey:[lastFmUsernames objectAtIndex:j]];
            }
        }
        
        self.title = @"Suggestions";
        
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Cancel"
                                                                                 style:UIBarButtonItemStylePlain
                                                                                target:self
                                                                                action:@selector(cancel)];
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Proceed"
                                                                                  style:UIBarButtonItemStyleDone
                                                                                 target:self
                                                                                 action:@selector(proceed)];
        
        [self initializeForm];
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
}

- (void)initializeForm
{
    XLFormDescriptor* form;
    XLFormSectionDescriptor* section;
    XLFormRowDescriptor* row;
    
    form = [XLFormDescriptor formDescriptor];
    [form setDelegate:self];
    self.form = form;
    
    section = [XLFormSectionDescriptor formSection];
    section.title = NSLocalizedString(@"Recommend", nil);
    [form addFormSection:section];
    
    row = [XLFormRowDescriptor formRowDescriptorWithTag:@"type"
                                                rowType:@"selectorActionSheet"
                                                  title:NSLocalizedString(@"Type", nil)];
    row.selectorOptions = @[@"Albums", @"Tracks"];
    row.value = @"Albums";
    [section addFormRow:row];
    
    row = [XLFormRowDescriptor formRowDescriptorWithTag:@"lastFmUsername"
                                                rowType:@"selectorActionSheet"
                                                  title:NSLocalizedString(@"From", nil)];
    row.selectorOptions = self.friends;
    row.value = [self.friends objectAtIndex:0];
    [section addFormRow:row];
    
    row = [XLFormRowDescriptor formRowDescriptorWithTag:@"period"
                                                rowType:@"selectorActionSheet"
                                                  title:NSLocalizedString(@"For period", nil)];
    row.selectorOptions = @[@"Week", @"Month", @"3 months", @"Half-year", @"Year", @"Custom"];
    row.value = @"Week";
    [section addFormRow:row];
    
    row = [XLFormRowDescriptor formRowDescriptorWithTag:@"sort"
                                                rowType:@"selectorActionSheet"
                                                  title:NSLocalizedString(@"Order by", nil)];
    row.selectorOptions = @[@"Scrobbles count", @"Random"];
    row.value = @"Scrobbles count";
    [section addFormRow:row];
    
    section = [XLFormSectionDescriptor formSection];
    section.title = NSLocalizedString(@"Genres", nil);
    [form addFormSection:section];
    
    row = [XLFormRowDescriptor formRowDescriptorWithTag:@"includeGenres"
                                                rowType:@"multipleSelector"
                                                  title:NSLocalizedString(@"Include", nil)];
    row.selectorOptions = @[];
    row.value = @[];
    [section addFormRow:row];
    
    row = [XLFormRowDescriptor formRowDescriptorWithTag:@"excludeGenres"
                                                rowType:@"multipleSelector"
                                                  title:NSLocalizedString(@"Exclude", nil)];
    row.selectorOptions = @[];
    row.value = @[];
    [section addFormRow:row];
    
    [self loadGenres];
    
    section = [XLFormSectionDescriptor formSection];
    section.title = NSLocalizedString(@"Restrictions", nil);
    [form addFormSection:section];
    
    row = [XLFormRowDescriptor formRowDescriptorWithTag:@"minScrobblesCount"
                                                rowType:@"integer"
                                                  title:NSLocalizedString(@"Min scrobbles count", nil)];
    [row.cellConfig setObject:@(NSTextAlignmentRight) forKey:@"textField.textAlignment"];
    row.value = @(2);
    [section addFormRow:row];
    
    row = [XLFormRowDescriptor formRowDescriptorWithTag:@"limit"
                                                rowType:@"integer"
                                                  title:NSLocalizedString(@"Limit", nil)];
    [row.cellConfig setObject:@(NSTextAlignmentRight) forKey:@"textField.textAlignment"];
    row.value = @(50);
    [section addFormRow:row];
}

-(void)formRowDescriptorValueHasChanged:(XLFormRowDescriptor*)rowDescriptor oldValue:(id)oldValue newValue:(id)newValue
{
    [super formRowDescriptorValueHasChanged:rowDescriptor oldValue:oldValue newValue:newValue];
    
    if ([rowDescriptor.tag isEqualToString:@"lastFmUsername"])
    {
        [self loadGenres];
    }
    
    if ([rowDescriptor.tag isEqualToString:@"period"])
    {
        if ([[rowDescriptor.value valueData] isEqualToString:@"Week"])
        {
            [self.form formRowWithTag:@"minScrobblesCount"].value = @(2);
        }
        else if ([[rowDescriptor.value valueData] isEqualToString:@"Month"])
        {
            [self.form formRowWithTag:@"minScrobblesCount"].value = @(5);
        }
        else if ([[rowDescriptor.value valueData] isEqualToString:@"3 months"])
        {
            [self.form formRowWithTag:@"minScrobblesCount"].value = @(7);
        }
        else
        {
            [self.form formRowWithTag:@"minScrobblesCount"].value = @(10);
        }
        
        if ([[rowDescriptor.value valueData] isEqualToString:@"Custom"])
        {
            XLFormRowDescriptor* startRow = [XLFormRowDescriptor formRowDescriptorWithTag:@"customDateStart"
                                                                                  rowType:@"dateInline"
                                                                                    title:NSLocalizedString(@"Period start", nil)];
            startRow.value = [self.dateFormatter dateFromString:@"2011-01-01T00:00:00"];
            
            XLFormRowDescriptor* endRow = [XLFormRowDescriptor formRowDescriptorWithTag:@"customDateEnd"
                                                                                rowType:@"dateInline"
                                                                                  title:NSLocalizedString(@"Period end", nil)];
            endRow.value = [self.dateFormatter dateFromString:@"2020-01-01T00:00:00"];
            
            [self.form addFormRow:startRow afterRow:rowDescriptor];
            [self.form addFormRow:endRow afterRow:startRow];
        }
        else
        {
            
            [self.form removeFormRowWithTag:@"customDateStart"];
            [self.form removeFormRowWithTag:@"customDateEnd"];
        }
    }
}

- (void)loadGenres
{
    NSMutableArray* genresNames = [NSMutableArray array];
    
    NSArray* genres = [self genresForCurrentUser];
    if (genres)
    {
        for (int i = 0; i < genres.count; i++)
        {
            [genresNames addObject:[[genres objectAtIndex:i] objectForKey:@"name"]];
        }
    }
    
    [self.form formRowWithTag:@"includeGenres"].selectorOptions = genresNames;
    [self.form formRowWithTag:@"excludeGenres"].selectorOptions = genresNames;
}

- (NSArray*)genresForCurrentUser
{
    NSData* data = [NSData dataWithContentsOfFile:
                    [NSString stringWithFormat:
                     @"%@/%@/genres.json",
                     librariesPath,
                     [[self.friendPlayer objectForKey:
                       [self.form formRowWithTag:@"lastFmUsername"].value]
                      objectForKey:@"libraryPath"]]];
    if (data)
    {
        return [NSJSONSerialization JSONObjectWithData:data
                                               options:0
                                                 error:nil];
    }
    
    return nil;
}

- (void)cancel
{
    [self dismissViewControllerAnimated:YES completion:^{
    }];
}

- (void)proceed
{
    NSString* type = [self.form formRowWithTag:@"type"].value;
    NSString* from = [self.form formRowWithTag:@"lastFmUsername"].value;
    NSString* period = [self.form formRowWithTag:@"period"].value;
    
    RecommendationsAction action = 0;
    if ([type isEqualToString:@"Albums"])
    {
        action = RecommendationsShowInController;
    }
    if ([type isEqualToString:@"Tracks"])
    {
        action = RecommendationsAddToPlaylist;
    }
    
    NSDictionary* player = [self.friendPlayer objectForKey:from];
    
    NSString* url = [NSString stringWithFormat:
                     @"%@/recommendations/for/%@/from/%@?type=%@&min-scrobbles-count=%d&sort=%@&limit=%d",
                     [player objectForKey:@"url"],
                     lastFmUsername,
                     from,
                     @{@"Albums": @"directory",
                       @"Tracks": @"file"}[type],
                     [[self.form formRowWithTag:@"minScrobblesCount"].value intValue],
                     @{@"Scrobbles count": @"scrobbles-count",
                       @"Random": @"random"}[[self.form formRowWithTag:@"sort"].value],
                     [[self.form formRowWithTag:@"limit"].value intValue]];
    
    ASIFormDataRequest* asiRequest = [[ASIFormDataRequest alloc] init];
    [asiRequest setStringEncoding:NSUTF8StringEncoding];
    
    NSArray* includeGenres = [self.form formRowWithTag:@"includeGenres"].value;
    NSArray* excludeGenres = [self.form formRowWithTag:@"excludeGenres"].value;
    NSArray* genres = [self genresForCurrentUser];
    for (int i = 0; i < includeGenres.count; i++)
    {
        for (int j = 0; j < genres.count; j++)
        {
            if ([includeGenres[i] isEqualToString:genres[j][@"name"]])
            {
                url = [url stringByAppendingString:
                       [NSString stringWithFormat:@"&include-dir=%@",
                        [asiRequest encodeURL:genres[j][@"path"]]]];
            }
        }
    }
    for (int i = 0; i < excludeGenres.count; i++)
    {
        for (int j = 0; j < genres.count; j++)
        {
            if ([excludeGenres[i] isEqualToString:genres[j][@"name"]])
            {
                url = [url stringByAppendingString:
                       [NSString stringWithFormat:@"&exclude-dir=%@",
                        [asiRequest encodeURL:genres[j][@"path"]]]];
            }
        }
    }
    
    if ([period isEqualToString:@"Custom"])
    {
        url = [url stringByAppendingString:
               [NSString stringWithFormat:@"&datetime-start=%@&datetime-end=%@",
                [asiRequest encodeURL:[self.dateFormatter stringFromDate:
                                       [self.form formRowWithTag:@"customDateStart"].value]],
                [asiRequest encodeURL:[self.dateFormatter stringFromDate:
                                       [self.form formRowWithTag:@"customDateEnd"].value]]]];
    }
    else
    {
        url = [url stringByAppendingString:
               [NSString stringWithFormat:@"&datetime-start=%@",
                [asiRequest encodeURL:[self.dateFormatter stringFromDate:
                                       [NSDate dateWithTimeIntervalSinceNow:
                                        -[@{@"Week": @(7 * 86400),
                                            @"Month": @(30 * 86400),
                                            @"3 months": @(90 * 86400),
                                            @"Half-year": @(180 * 86400),
                                            @"Year": @(365 * 86400)}[period] intValue]]]]]];
    }
    
    [asiRequest release];
    
    [self dismissViewControllerAnimated:YES completion:^{
    }];
    [recommendationsUtils processRecommendationsUrl:[NSURL URLWithString:url]
                                         withPlayer:player
                                              title:[NSString stringWithFormat:
                                                     @"%@'s recommendations",
                                                     from]
                                             action:action];
}

@end
