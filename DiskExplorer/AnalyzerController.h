//
//  AnalyzerController.h
//  DiskExplorer
//
//  Created by Michael Larson on 1/30/14.
//  Copyright (c) 2014 Sandstorm Software. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "ResourceMgr.h"
#import "OutlineView.h"

@interface AnalyzerController : NSObject <NSOutlineViewDataSource, NSOutlineViewDelegate>
{
    ResourceMgr     *_resmgr;
    OutlineView     *_analyzeView;
    
    NSTextField     *_infoField;
    NSTimer         *_timer;

    unsigned        _update;
    bool            _threadRunning;
    OSSpinLock      _lock;
    
    bool            _analyzeComplete;
    bool            _pauseContinue;

    int             _sortMode;
    int             _sortDir;
}

-(id)initWithResourceMgr: (ResourceMgr *)mgr forView: (OutlineView *)outlineView;
-(void)analyzeFiles: (id)sender;
-(bool)complete;

@end
