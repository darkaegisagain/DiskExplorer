//
//  AppDelegate.m
//  DiskExplorer
//
//  Created by Michael Larson on 10/28/13.
//  Copyright (c) 2013 Sandstorm Software. All rights reserved.
//

#import "AppDelegate.h"
#import <CoreServices/CoreServices.h>
#import <QuickLook/QuickLook.h>
#import <dispatch/dispatch.h>
#import <mach/mach.h>
#import <mach/mach_time.h>
#include <sys/mman.h>

//#include "re2/re2/re2.h"

//#define calloc(a, b)    calloc(a, b)

@implementation AppDelegate

- (OutlineView *) initOutlineViewForTab: (NSInteger)tabNum
{
    OutlineView *ret;
    
    NSRect          frame = [[[_tabView tabViewItemAtIndex: tabNum] view] frame];
    NSScrollView    *scrollView = [[NSScrollView alloc] initWithFrame: frame];
    NSSize          size = [scrollView contentSize];
    
    ret = [[OutlineView alloc] initWithFrame: NSMakeRect(0, 0, size.width, size.height)];
    
    // NSOutlineView
    NSString *headerNames[] = {@"Filename", @"Size", @"File Count", NULL};
    for(int i=0;headerNames[i];i++)
    {
        NSTableColumn   *column = [[NSTableColumn alloc] initWithIdentifier: headerNames[i]];
        
        [ret addTableColumn: column];
        
        if(i == 0)
        {
            [column setWidth: size.width - 2 * COLUMN_WIDTH];
            [ret setOutlineTableColumn: [[ret tableColumns] objectAtIndex: i]];

            //[column setResizingMask: NSTableColumnAutoresizingMask];
        }
        else
        {
            //[column setResizingMask: NSTableColumnNoResizing];
            
            [column setWidth: COLUMN_WIDTH];
        }
    }
    
    [scrollView setDocumentView: ret];
    [scrollView setHasVerticalScroller:YES];
    
    [[_tabView tabViewItemAtIndex: tabNum] setView: scrollView];
    
    for(int i=0;headerNames[i];i++)
    {
        NSTableColumn *column = [[ret tableColumns] objectAtIndex:i];
        
        [[column headerCell] setTitle: headerNames[i]];
    }

    [ret setAutoresizesSubviews:YES];
    [ret setAllowsColumnSelection: FALSE];
    [ret setUsesAlternatingRowBackgroundColors: TRUE];
    [ret setAllowsColumnResizing: TRUE];
    [ret setColumnAutoresizingStyle: NSTableViewReverseSequentialColumnAutoresizingStyle];
    [ret setAllowsMultipleSelection: YES];
    
    ImageAndTextCell *imageAndTextCell = [[[ImageAndTextCell alloc] init] autorelease];
    [[[ret tableColumns] objectAtIndex:kFileNameColumn] setDataCell: imageAndTextCell];
    
    TextCell *textCell = [[[TextCell alloc] init] autorelease];
    [[[ret tableColumns] objectAtIndex:kSizeColumn] setDataCell: textCell];
    
    textCell = [[[TextCell alloc] init] autorelease];
    [[[ret tableColumns] objectAtIndex:kFileCountColumn] setDataCell: textCell];
    
    [ret sizeToFit];

    return ret;
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    _searchCount = 0;
    _searchResults = NULL;
    
    _analyzeTimer = NULL;
    _duplicateTimer = NULL;
    
    _resourceMgr = [[ResourceMgr alloc] init];
    
    [_tabView autoresizesSubviews];
    [_tabView display];
    
    [_actionButton setTitle: @"Analyze"];
    [_actionButton setAction: @selector(analyzeFiles:)];
    
    _analyzerOutlineView = [self initOutlineViewForTab: 0];
    _duplicatesOutlineView = [self initOutlineViewForTab: 1];
    
    _analyzerController = [[AnalyzerController alloc] initWithResourceMgr:_resourceMgr forView: _analyzerOutlineView];
    _duplicateController = [[DuplicatesController alloc] initWithResourceMgr: _resourceMgr forView: _duplicatesOutlineView];

    [_tabView selectTabViewItemAtIndex: 0];
    
    [_tabView setDelegate: self];
}

#pragma mark NSTabView delegates
- (void)alertDidEndForFindDuplicates:(NSAlert *)alert returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo
{
    // user pressed ok
    if(returnCode == NSAlertFirstButtonReturn)
    {
        [_tabView selectTabViewItemAtIndex: 0];
    }
}

-(void)checkAnalyzeStatus:(id)ptr
{
    if([[_tabView tabViewItems] indexOfObject: [_tabView selectedTabViewItem]] == 0)
    {
        size_t  directory_count = gEntryTracking._directory_count;
        size_t  file_count = gEntryTracking._file_count;
        size_t  total_size = gEntryTracking._size;
        size_t  mByte = 1024 * 1024;
        size_t  gByte = mByte * 1024;
        size_t  tByte = gByte * 1024;
        
        const char *sizeUnit[] = {"Bytes", "MBytes", "GBytes", "TBytes"};
        int sizeIndex = 0;
        
        if(total_size > tByte)
        {
            total_size /= tByte;
            sizeIndex = 3;
        }
        else if(total_size > gByte)
        {
            total_size /= gByte;
            sizeIndex = 2;
        }
        else if(total_size > mByte)
        {
            total_size /= mByte;
            sizeIndex = 1;
        }
        
        NSString *infoString = [[NSString alloc] initWithFormat: @"%zu files\n%zu directories\n%zu %s", file_count, directory_count, total_size, sizeUnit[sizeIndex]];
        
        [_info setStringValue: infoString];
    }
    
    if([_analyzerController complete])
    {
        if(_duplicateTimer == NULL)
        {
            [_progress stopAnimation: self];
        }
        
        if([[_tabView tabViewItems] indexOfObject: [_tabView selectedTabViewItem]] == 0)
        {
            [_actionButton setEnabled: false];
        }
        
        if(_analyzeTimer)
        {
            [_analyzeTimer invalidate];

            _analyzeTimer = NULL;
        }
    }
}

-(void)analyzeFiles: (id)sender
{
    [_actionButton setEnabled: false];
    
    [_progress startAnimation: self];
    
    _analyzeTimer = [NSTimer scheduledTimerWithTimeInterval: 1.0f / 5.0f target: self selector: @selector(checkAnalyzeStatus:) userInfo: NULL repeats: YES];

    [_analyzerController analyzeFiles: sender];
}

-(void)checkDuplicatesStatus:(id)ptr
{
    if([[_tabView tabViewItems] indexOfObject: [_tabView selectedTabViewItem]] == 1)
    {
        size_t  file_count = gDuplicatesInfo._count;
        size_t  total_size = gDuplicatesInfo._size;
        size_t  mByte = 1024 * 1024;
        size_t  gByte = mByte * 1024;
        size_t  tByte = gByte * 1024;
        
        const char *sizeUnit[] = {"Bytes", "MBytes", "GBytes", "TBytes"};
        int sizeIndex = 0;
        
        if(total_size > tByte)
        {
            total_size /= tByte;
            sizeIndex = 3;
        }
        else if(total_size > gByte)
        {
            total_size /= gByte;
            sizeIndex = 2;
        }
        else if(total_size > mByte)
        {
            total_size /= mByte;
            sizeIndex = 1;
        }
        
        NSString *infoString = [[NSString alloc] initWithFormat: @"%zu duplicate files\n%zu %s", file_count, total_size, sizeUnit[sizeIndex]];
        
        [_info setStringValue: infoString];
    }
    
    if([_duplicateController complete])
    {
        if(_analyzeTimer == NULL)
        {
            [_progress stopAnimation: self];
        }
        
        if([[_tabView tabViewItems] indexOfObject: [_tabView selectedTabViewItem]] == 1)
        {
            [_actionButton setEnabled: false];
        }

        if(_duplicateTimer)
        {
            [_duplicateTimer invalidate];
        
            _duplicateTimer = NULL;
        }
    }
}

-(void)findDuplicates: (id)sender
{
    [_actionButton setEnabled: false];
    
    [_progress startAnimation: self];
    
    _duplicateTimer = [NSTimer scheduledTimerWithTimeInterval: 1.0f / 5.0f target: self selector: @selector(checkDuplicatesStatus:) userInfo: NULL repeats: YES];

    [_duplicateController findDuplicates: sender];
}

- (void)tabView:(NSTabView *)tabView didSelectTabViewItem:(NSTabViewItem *)tabViewItem;
{
    OutlineView *outlineView = NULL;
    
    [_tabView display];
    
    switch([[_tabView tabViewItems] indexOfObject: tabViewItem])
    {
        case 0:
            outlineView = _analyzerOutlineView;
            
            [_actionButton setTitle: @"Analyze"];
            [_actionButton setAction: @selector(analyzeFiles:)];
            if([_analyzerController complete])
            {
                [_actionButton setEnabled: 0];
            }
            else
            {
                [_actionButton setEnabled: 1];
            }
            [self checkAnalyzeStatus: NULL];
            break;
            
        case 1:
            outlineView = _duplicatesOutlineView;
            
            if([_analyzerController complete] == false)
            {
                NSAlert *alert = [[[NSAlert alloc] init] autorelease];
                [alert addButtonWithTitle:@"Ok"];
                [alert setMessageText:@"Analyze Files must be complete to find duplicates"];
                
                [alert setAlertStyle:NSWarningAlertStyle];
                [alert beginSheetModalForWindow:[_analyzerOutlineView window] modalDelegate:self didEndSelector:@selector(alertDidEndForFindDuplicates:returnCode:contextInfo:) contextInfo: NULL];
            }
            else
            {
                [_actionButton setTitle: @"Find Duplicates"];
                [_actionButton setAction: @selector(findDuplicates:)];

                if([_duplicateController complete] == false)
                {
                    [_actionButton setEnabled: 1];
                }
                else
                {
                    [_actionButton setEnabled: 0];
                }
            }
            
            [self checkDuplicatesStatus: NULL];
            break;
    }
    
    if(outlineView)
    {
        [outlineView reloadData];
        [outlineView reloadItem: NULL];
        [outlineView sizeToFit];
    }
}

#pragma mark search field delegates


@end
