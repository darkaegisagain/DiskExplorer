//
//  ResourceMgr.m
//  DiskExplorer
//
//  Created by Michael Larson on 2/3/14.
//  Copyright (c) 2014 Sandstorm Software. All rights reserved.
//

#import "ResourceMgr.h"

@implementation ResourceMgr

-(id)init
{
    // init file icons cache
    _fileIcons = [[NSMutableDictionary alloc] init];

    char *user_name = strdup([NSUserName() fileSystemRepresentation]);
    char *user_path = strdup([[NSHomeDirectory() stringByDeletingLastPathComponent] fileSystemRepresentation]);
    
    Entry *parent = [[Entry alloc] init];
    
    parent->_type = DT_DIR;
    parent->_name = strdup(user_name);
    parent->_path = strdup(user_path);
    parent->_parent = NULL;
    
#if 1
    char *commonDirectories[] = {"Applications",
        "Desktop",
        "Documents",
        "Downloads",
        "Library",
        "Movies",
        "Music",
        "Pictures",
        "Public",
        NULL};
#else
    char *commonDirectories[] = {"Downloads",
        "Documents",
//        "Pictures",
        "Music",
        "Desktop",
        NULL};
#endif
        
    parent->_entries = [[NSMutableArray alloc] init];
    
    for(int i=0; commonDirectories[i]; i++)
    {
        Entry *temp = [[Entry alloc] init];
        
        temp->_type = DT_DIR;
        temp->_parent = parent;
        temp->_name = strdup(commonDirectories[i]);
        temp->_path = malloc(strlen(user_path) + strlen(user_name) + strlen(commonDirectories[i]) + 16);
        sprintf(temp->_path, "%s/%s/%s", user_path, user_name, commonDirectories[i]);
        
        temp = [temp entryWithName: commonDirectories[i] withParent: parent withEntry: temp recursiveSearch: false];
        
        OSSpinLockCall(parent->_lock, [parent->_entries addObject: temp]);
    }
    
    _entries = parent;
    
    return [super init];
}

-(Entry *)entries
{
    return _entries;
}

- (NSImage *)iconForFile: (NSString *)path
{
    NSString *ext = [path pathExtension];
    NSImage *image = NULL;
    
    // no file ext
    if([ext length] == 0)
    {
        if([_fileIcons count])
        {
            image = [_fileIcons objectForKey: path];
            
            if(image)
                return image;
        }
        
        image = [[NSWorkspace sharedWorkspace] iconForFile: path];
        
        [_fileIcons setObject:image forKey: path];
        
        return image;
    }
    
    if([_fileIcons count])
    {
        image = [_fileIcons objectForKey: path];
        
        if(image)
            return image;
    }
    
    image = [[NSWorkspace sharedWorkspace] iconForFile: path];
    
    
    [_fileIcons setObject:image forKey: path];
    
    return image;
}


@end
