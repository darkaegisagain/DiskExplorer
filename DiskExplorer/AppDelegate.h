//
//  AppDelegate.h
//  DiskExplorer
//
//  Created by Michael Larson on 10/28/13.
//  Copyright (c) 2013 Sandstorm Software. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "Entry.h"
#import "ImageAndTextCell.h"
#import "TextCell.h"
#import "OutlineView.h"
#import "AnalyzerController.h"
#import "DuplicatesController.h"

typedef unsigned SortMode;

@interface AppDelegate : NSObject <NSApplicationDelegate, NSOutlineViewDataSource, NSOutlineViewDelegate, NSTabViewDelegate, NSTextFieldDelegate>
{
    IBOutlet NSWindow               *_window;
    IBOutlet NSTabView              *_tabView;
    
    IBOutlet NSButton               *_actionButton;
    
    IBOutlet NSProgressIndicator    *_progress;
    IBOutlet NSTextField            *_info;
    
    ResourceMgr             *_resourceMgr;
    
    OutlineView             *_analyzerOutlineView;
    OutlineView             *_duplicatesOutlineView;

    AnalyzerController      *_analyzerController;
    DuplicatesController    *_duplicateController;
    
    NSTimer                 *_analyzeTimer;
    NSTimer                 *_duplicateTimer;
    
    int32_t                 _searchCount;
    NSMutableArray          *_searchResults;
}

@property (readwrite, strong) ImageAndTextCell *_imageCell;

@end
