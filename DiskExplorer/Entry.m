//
//  Entry.m
//  DiskExplorer
//
//  Created by Michael Larson on 10/28/13.
//  Copyright (c) 2013 Sandstorm Software. All rights reserved.
//

#import "Entry.h"
#import <mach/mach.h>
#import <mach/mach_time.h>

EntryTracking gEntryTracking;

@implementation Entry

-(id)init
{
    self = [super init];

    _lock        = 0;
    _type        = 0;
    _parent      = NULL;
    _name        = NULL;
    _size        = 0;
    _file_count  = 0;
    _directory_count         = 0;
    _explored                = false;
    _entries                 = NULL;
    
    _first_256_bytes_hash    = 0;
    _full_hash_generated     = 0;

    return self;
}

-(id)initWithName: (NSString *)name
{
    self = [self init];
    
    return self;
}

-(void)print
{
    printf("Parent              %p\n", _parent);
    printf("Name                %s\n", _name);
    printf("Type                %d\n", _type);
    printf("Size                %zu\n", _size);
    printf("File Count          %zu\n", _file_count);
    printf("Directory Count     %zu\n", _directory_count);
    printf("Explored            %d\n", _explored);
}

- (void)strcatParent: (char *)str;
{
    if(_parent)
    {
        [_parent strcatParent: str];
    }
    
    if(_parent == NULL)
    {
        strcat(str, _path);
        strcat(str, "/");
    }
    
    strcat(str, _name);
    strcat(str, "/");
}

- (char *)genFullPath
{
    Entry       *__parent = _parent;
    size_t      len = strlen(_name);
    unsigned    dirCount = 1;
    
    while(__parent)
    {
        dirCount++;
        len += strlen(__parent->_name);
        __parent = __parent->_parent;
    }
    
    char    *ret = (char *)calloc(1, len + dirCount);
    
    [_parent strcatParent: ret];
    
    strcat(ret, _name);
    
    return ret;
}

- (size_t) getFullPathLen: (Entry *)entry forPath: (char *)name
{
    return strlen(entry->_path) + strlen(name);
}

- (void) strcpyFullPath: (Entry *)entry forPath: (char *)name inBuf:(char *)buf
{
    char *src;
    char *dst = buf;
    
    if(entry)
        src = entry->_path;
    else
        src = name;
    
    while(*src)
    {
        *dst++ = *src++;
    }
    
    *dst++ = '/';
    
    src = name;
    while(*src)
    {
        *dst++ = *src++;
    }
    
    *dst++ = 0;
}

-(char *)genFullPath: (Entry *)entry forPath: (char *)name
{
    size_t      len = [self getFullPathLen: entry forPath: name];
    char        *fullPath = malloc(len + 4);
    
    [self strcpyFullPath: entry forPath: name inBuf: fullPath];
    
    return fullPath;
}

-(char *)genPath: (Entry *)entry forName: (char *)name
{
    size_t      len = [self getFullPathLen: entry forPath: name];
    char        *fullPath = malloc(len + 4);
    
    [self strcpyFullPath: entry forPath: name inBuf: fullPath];
    
    return fullPath;
}

- (Entry *)entryWithName: (char *)name withParent: (Entry *)parent withEntry: (Entry *)entry recursiveSearch: (bool) recurse
{
    DIR         *d;
    
    if(entry == NULL)
    {
        entry = [[Entry alloc] init];
        
        entry->_type = DT_DIR;
        entry->_name = strdup(name);
        entry->_path = [entry genPath: parent forName: name];
        entry->_parent = parent;
    }
    
    if(entry->_entries == NULL)
    {
        /* Open the current directory. */
        d = opendir (entry->_path);
        
        if (!d)
        {
#if __DEBUG__
            fprintf(stderr, "%s unable to open directory %s\n", __FUNCTION__, entry->_path);
#endif
            return NULL;
        }
        
        struct dirent   *dir_entry;
        
        while (1)
        {
            dir_entry = readdir(d);
            
            if(!dir_entry)
                break;
            
            if(dir_entry->d_name[0] == '.' && dir_entry->d_name[1] == 0)
            {
                // ignore current directory
            }
            else if(dir_entry->d_name[0] == '.' && dir_entry->d_name[1] == '.' && dir_entry->d_name[2] == 0)
            {
                // ignore prev directory
            }
            else if(dir_entry->d_name[0] == '.')
            {
                // ignore hidden files
            }
            else
            {
                switch(dir_entry->d_type)
                {
                    case DT_DIR:
                    {
                        Entry *new_entry = [[Entry alloc] init];
                        
                        new_entry->_type = DT_DIR;
                        new_entry->_name = strdup(dir_entry->d_name);
                        new_entry->_path = [entry genPath: entry forName: new_entry->_name];
                        new_entry->_parent = entry;
                        
                        if(entry->_entries == NULL)
                        {
                            entry->_entries = [[NSMutableArray alloc] initWithCapacity: 1];
                        }
                        
                        gEntryTracking._directory_count++;
                        
                        OSSpinLockCall(entry->_lock, [entry->_entries addObject: new_entry]);
                    }
                        break;
                        
                    case DT_REG:
                    {
                        if(entry->_entries == NULL)
                        {
                            entry->_entries = [[NSMutableArray alloc] initWithCapacity: 1];
                        }
                        
                        Entry *new_entry = [[Entry alloc] init];
                        
                        new_entry->_type = DT_REG;
                        new_entry->_name = strdup(dir_entry->d_name);
                        new_entry->_path = NULL;
                        new_entry->_parent = entry;
                        
                        size_t len = strlen(entry->_path) + strlen(new_entry->_name) + 4;
                        
                        char *temp = malloc(len);
                        
                        sprintf(temp, "%s/%s", entry->_path, new_entry->_name);
                        
                        struct stat     stbuf;
                        
                        if (stat(temp, &stbuf) == 0)
                        {
                            new_entry->_size = stbuf.st_size;
                            gEntryTracking._size += stbuf.st_size;
                        }
                        
                        free(temp);
                        
                        gEntryTracking._file_count++;
                        
                        OSSpinLockCall(entry->_lock, [entry->_entries addObject: new_entry]);
                    }
                        break;
                        
                    default:
                        break;
                }
            }
        }
        
        /* Close the directory. */
        closedir(d);
    }
    
    /* go through all directories in entry and build them out */
    if(recurse)
    {
        for(int i=0; i<[entry->_entries count]; i++)
        {
            Entry *testEntry = (Entry *)[entry->_entries objectAtIndex: i];
            
            if(testEntry->_type == DT_DIR)
            {
                if([self entryWithName: testEntry->_name withParent: entry withEntry: testEntry recursiveSearch: recurse] == NULL)
                {
                    OSSpinLockCall(entry->_lock, [entry->_entries removeObjectAtIndex: i]);
                }
            }
        }
        
        entry->_explored = TRUE;
    }
    
    [self recalculateSize: entry];
    
    return entry;
}

-(void)recalculateSize:(Entry *)entry
{
    if(entry->_type == DT_DIR)
    {
        entry->_size = 0;
        entry->_file_count = 0;
        
        for(int i=0; i<[entry->_entries count]; i++)
        {
            Entry *testEntry = (Entry *)[entry->_entries objectAtIndex: i];
            
            if(testEntry->_type == DT_DIR)
            {
                [self recalculateSize: testEntry];
                
                entry->_file_count += testEntry->_file_count;
            }
            else
            {
                entry->_file_count++;
            }
            
            entry->_size += testEntry->_size;
        }
    }
}

NSInteger compareEntrySize(id ptr1, id ptr2, void *context)
{
    Entry       *a = (Entry *)ptr1;
    Entry       *b = (Entry *)ptr2;
    int         dir = *(int *)context;
    
    if(a->_size < b->_size)
        return NSOrderedDescending * dir;
    else if(a->_size == b->_size)
        return NSOrderedSame * dir;
    
    return NSOrderedAscending * dir;
}

NSInteger compareEntryFileName(id ptr1, id ptr2, void *context)
{
    Entry       *a = (Entry *)ptr1;
    Entry       *b = (Entry *)ptr2;
    int         dir = *(int *)context;
    int         result;
    
    if(a->_type == b->_type)
    {
        if(a->_type == DT_DIR)
        {
            result = strcmp(a->_path, b->_path);
        }
        else
        {
            result = strcmp(a->_name, b->_name);
        }
        
        if(result < 0)
            return NSOrderedDescending * dir;
        else if(result == 0)
            return NSOrderedSame * dir;
        
        return NSOrderedAscending * dir;
    }
    else if(a->_type == DT_DIR)
    {
        return NSOrderedDescending * dir;
    }
    else if(b->_type == DT_DIR)
    {
        return NSOrderedAscending * dir;
    }
    
    return NSOrderedAscending * dir;
}

NSInteger compareEntryFileCount(id ptr1, id ptr2, void *context)
{
    Entry       *a = (Entry *)ptr1;
    Entry       *b = (Entry *)ptr2;
    int         dir = *(int *)context;
    
    if(a->_file_count < b->_file_count)
        return NSOrderedDescending * dir;
    else if(a->_file_count == b->_file_count)
        return NSOrderedSame * dir;
    
    return NSOrderedAscending * dir;
}

-(void)sortEntries:(Entry *)entry mode:(unsigned)sortMode direction:(int)sortDir
{
    switch(sortMode)
    {
        case kSortSize:
            [entry->_entries sortUsingFunction: compareEntrySize context: &sortDir];
            break;
            
        case kSortFileName:
            [entry->_entries sortUsingFunction: compareEntryFileName context: &sortDir];
            break;
            
        case kSortFileCount:
            [entry->_entries sortUsingFunction: compareEntryFileCount context: &sortDir];
            break;
    }
}

-(void)calculateFilesAndFolderCount:(Entry *)entry
{
    size_t  file_count = 0;
    size_t  directory_count = 0;
    
    for(int i=0; i<[entry->_entries count]; i++)
    {
        Entry *testEntry = (Entry *)[entry->_entries objectAtIndex: i];
        
        if(testEntry->_type == DT_DIR)
        {
            directory_count++;
            
            [self calculateFilesAndFolderCount: testEntry];
            
            file_count += testEntry->_file_count;
            directory_count += testEntry->_directory_count;
        }
        else
        {
            file_count++;
        }
    }
    
    entry->_file_count = file_count;
    entry->_directory_count = directory_count;
}

@end
