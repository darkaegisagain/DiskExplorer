//
//  DuplicatesController.h
//  DiskExplorer
//
//  Created by Michael Larson on 2/1/14.
//  Copyright (c) 2014 Sandstorm Software. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "ResourceMgr.h"
#import "OutlineView.h"

#define HASH_TABLE_SIZE     0x10000
#define HASH_TABLE_MASK     0x0ffff

typedef struct {
    volatile int64_t    _count;
    volatile int64_t    _size;
} DuplicatesInfo;

extern DuplicatesInfo gDuplicatesInfo;

@interface DuplicatesController : NSObject <NSOutlineViewDataSource, NSOutlineViewDelegate>
{
    ResourceMgr     *_resmgr;
    OutlineView     *_duplicateView;
    HashEntry       *_hashTable;
    
    NSTextField     *_infoField;
    NSTimer         *_timer;
    unsigned        _update;
    bool            _threadRunning;
    OSSpinLock      _lock;

    bool            _findDuplicatesComplete;
    
    bool            _alertDone;
    bool            _continueTesting;
    
    NSMutableArray  *_duplicates;

    int             _sortMode;
    int             _sortDir;
}

-(id)initWithResourceMgr: (ResourceMgr *)mgr forView: (OutlineView *)outlineView;
-(void)findDuplicates: (id)sender;
-(bool)complete;

@end
