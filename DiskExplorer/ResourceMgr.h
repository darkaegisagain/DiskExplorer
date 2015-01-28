//
//  ResourceMgr.h
//  DiskExplorer
//
//  Created by Michael Larson on 2/3/14.
//  Copyright (c) 2014 Sandstorm Software. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "Entry.h"

@interface ResourceMgr : NSObject
{
    Entry                   *_entries;
    NSMutableDictionary     *_fileIcons;
}

-(id)init;
-(Entry *)entries;
-(NSImage *)iconForFile: (NSString *)path;

@end
