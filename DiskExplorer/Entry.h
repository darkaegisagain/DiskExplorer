//
//  Entry.h
//  DiskExplorer
//
//  Created by Michael Larson on 10/28/13.
//  Copyright (c) 2013 Sandstorm Software. All rights reserved.
//

#import <Foundation/Foundation.h>

#import <stdlib.h>
#import <stdint.h>
#import <assert.h>
#import <xmmintrin.h>
#import <ctype.h>

#import <sys/types.h>
#import <sys/stat.h>  /* structure returned by stat */
#import <sys/file.h>  /* flags for read and write */
#import <dirent.h>
#import <string.h>
#import <errno.h>

#define OSSpinLockCall(_lock_, _call_)  OSSpinLockLock(&_lock_); _call_; OSSpinLockUnlock(&_lock_)

enum {
    kSortSize,
    kSortFileName,
    kSortFileCount
};

typedef struct {
    size_t          _size;
    size_t          _file_count;
    size_t          _directory_count;
} EntryTracking;

extern EntryTracking gEntryTracking;

@interface Entry : NSObject
{
@public
    int             _type;
    Entry           *_parent;
    char            *_name;
    char            *_path;
    OSSpinLock      _lock;
    unsigned        _first_256_bytes_hash;
    unsigned        _full_hash_generated;
    unsigned char   _full_hash[32];
    unsigned        _duplicate;
    size_t          _size;
    size_t          _file_count;
    size_t          _directory_count;
    BOOL            _explored;
    NSMutableArray  *_entries;
}

-(void)print;

-(size_t) getFullPathLen: (Entry *)entry forPath: (char *)name;
-(void) strcpyFullPath: (Entry *)entry forPath: (char *)name inBuf:(char *)buf;
-(char *)genFullPath: (Entry *)entry forPath: (char *)name;
-(char *)genFullPath;
-(char *)genPath: (Entry *)entry forName: (char *)name;

- (Entry *)entryWithName: (char *)name withParent: (Entry *)parent withEntry: (Entry *)entry recursiveSearch: (bool) recurse;
-(void)recalculateSize:(Entry *)entry;
-(void)calculateFilesAndFolderCount:(Entry *)entry;
-(void)sortEntries:(Entry *)entry mode:(unsigned)sortMode direction:(int)sortDir;

NSInteger compareEntrySize(id ptr1, id ptr2, void *context);

@end

typedef struct HashEntry_t {
    struct HashEntry_t  *_prev, *_next;
    Entry               *_entry;
} HashEntry;


