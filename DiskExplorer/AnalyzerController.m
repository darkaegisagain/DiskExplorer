//
//  AnalyzerController.m
//  DiskExplorer
//
//  Created by Michael Larson on 1/30/14.
//  Copyright (c) 2014 Sandstorm Software. All rights reserved.
//

#import "AnalyzerController.h"
#import "ImageAndTextCell.h"
#import "TextCell.h"
#import <mach/mach.h>
#import <mach/mach_time.h>

@implementation AnalyzerController

-(id)initWithResourceMgr: (ResourceMgr *)mgr forView: (OutlineView *)outlineView;
{
    _resmgr = mgr;
    _analyzeView = outlineView;
    
    _sortMode = kSortSize;
    _sortDir = 1;
    
    [outlineView setDelegate: self];
    [outlineView setDataSource: self];

    return self;
}

-(bool)complete
{
    return _analyzeComplete;
}

// update done on main thread
- (void) reloadDirectoryView: (id) item
{
    [_analyzeView reloadItem: NULL reloadChildren: YES];
}

- (void) updateTimer: (NSTimer *)timer
{
    _update++;
}

// threaded routine to fill in size
-(void)directoryHuntThread: (NSMutableArray *) directoryEntries
{
    _update = 0;
    
    [NSThread setThreadPriority: 1.0];
    
    for(int j=0; j < [directoryEntries count]; j++)
    {
        Entry *entry = [directoryEntries objectAtIndex: j];
        
        if(([entry->_entries count] > 0) && (entry->_explored))
        {
            [entry->_entries sortUsingFunction: compareEntrySize context: &_sortDir];
        }
        
        entry->_size = 0;
        
        for(int i=0; i<[entry->_entries count]; i++)
        {
            Entry *testEntry = (Entry *)[entry->_entries objectAtIndex: i];
            
            if(testEntry->_type == DT_DIR)
            {
                if(_update)
                {
                    _update--;
                    
                    [self performSelectorOnMainThread: @selector(reloadDirectoryView:) withObject: _analyzeView waitUntilDone: YES];
                }
                
                if([entry entryWithName: testEntry->_name withParent: entry withEntry: testEntry recursiveSearch: true] == NULL)
                {
                    OSSpinLockCall(entry->_lock, [entry->_entries removeObjectAtIndex: i]);
                }

                [entry sortEntries: entry mode: _sortMode direction: _sortDir];
            }
        }
        
        [self performSelectorOnMainThread: @selector(reloadDirectoryView:) withObject: _analyzeView waitUntilDone: YES];
    }
    
    [directoryEntries release];
    
    [[_resmgr entries] recalculateSize: [_resmgr entries]];
    
    [[_resmgr entries] calculateFilesAndFolderCount: [_resmgr entries]];
    
    [_timer invalidate];
    
    [self performSelectorOnMainThread: @selector(reloadDirectoryView:) withObject: _analyzeView waitUntilDone: YES];
    
    _timer = NULL;
    _analyzeComplete = 1;
    _threadRunning = 0;
}

-(void)analyzeFiles: (id)sender
{
    if(_analyzeComplete == 0)
    {
        _threadRunning = 1;
        
        gEntryTracking._file_count = 0;
        gEntryTracking._directory_count = 0;
        gEntryTracking._size = 0;
        
        NSIndexSet      *selectedRows = [_analyzeView selectedRowIndexes];
        
        NSMutableArray  *directoryEntries = [[NSMutableArray alloc] init];
        
        if([selectedRows count] > 0)
        {
            for(NSUInteger i=[selectedRows firstIndex]; i<=[selectedRows lastIndex]; i++)
            {
                if([selectedRows containsIndex: i] == 0)
                    continue;
                
                Entry      *entry = (Entry *)[_analyzeView itemAtRow: i];
                
                [directoryEntries addObject: entry];
            }
        }
        else
        {
            [directoryEntries addObject: [_resmgr entries]];
        }
        
        [NSThread detachNewThreadSelector: @selector(directoryHuntThread:) toTarget: self withObject: directoryEntries];
        
        _timer = [NSTimer scheduledTimerWithTimeInterval: 1.0f / 5.0 target: self selector: @selector(updateTimer:) userInfo: NULL repeats: YES];
    }
}

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item
{
    Entry *entry = (Entry *)item;
    
    if(entry == NULL)
        entry = [_resmgr entries];
    
    if((entry->_type == DT_DIR) && (entry->_explored == FALSE))
    {
        [entry entryWithName: entry->_name withParent: entry->_parent withEntry: entry recursiveSearch: false];
    }
    
    if(entry->_type == DT_DIR)
    {
        [entry recalculateSize: entry];
    }
    
    if(entry->_type == DT_DIR)
    {
        NSString *path = [[NSString alloc] initWithUTF8String: entry->_path];
        
        NSString *ext = [path pathExtension];
        
        if([ext length] == 0)
        {
            [path release];
            [ext release];
            return [entry->_entries count];
        }
        
        NSString *noDigEntries[] = {@"app", @"pkg", NULL};
        
        for(int i=0; noDigEntries[i]; i++)
        {
            if([ext compare: noDigEntries[i]] == 0)
                return 0;
        }
    }
    
    return [entry->_entries count];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item
{
    Entry   *entry = (Entry *)item;
    
    if(entry == NULL)
        return false;
    
    if(entry->_type == DT_REG)
        return false;
    
    if((entry->_type == DT_DIR) && (entry->_explored == FALSE))
    {
        [entry entryWithName: entry->_name withParent: entry->_parent withEntry: entry recursiveSearch: false];
    }
    
    if(entry->_entries == NULL)
        return false;
    
    if(entry->_type == DT_DIR)
    {
        NSString *path = [[NSString alloc] initWithUTF8String: entry->_path];
        
        NSString *ext = [path pathExtension];
        
        if([ext length] == 0)
        {
            [path release];
            [ext release];
            return [entry->_entries count];
        }
        
        NSString *noDigEntries[] = {@"app", @"pkg", NULL};
        
        for(int i=0; noDigEntries[i]; i++)
        {
            if([ext compare: noDigEntries[i]] == 0)
                return 0;
        }
    }
    
    return [entry->_entries count] > 0;
}

- (id) outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item
{
    Entry   *entry = (Entry *)item;
    
    if(entry == NULL)
    {
        entry = [_resmgr entries];

        return [entry->_entries objectAtIndex: index];
    }
    
    if(entry->_type == DT_REG)
        return NULL;
    
    if(entry->_entries == NULL)
        return NULL;

    return [entry->_entries objectAtIndex: index];
}

- (NSCell *)outlineView:(NSOutlineView *)outlineView dataCellForTableColumn:(NSTableColumn *)tableColumn item:(id)item
{
    // printf("%s tableColumn: %p item: %p\n", __FUNCTION__, tableColumn, item);
    
    if(tableColumn == NULL)
        return NULL;
    
    NSUInteger col_index = [[outlineView tableColumns] indexOfObject: tableColumn];
    switch(col_index)
    {
        case kFileNameColumn:
        {
            Entry      *entry = (Entry *)item;

            if(entry->_type == DT_DIR)
            {
                NSString *fullPath = [[NSString alloc] initWithUTF8String: entry->_path];
                
                NSImage *image = [_resmgr iconForFile: fullPath];
                
                ImageAndTextCell *cell = [[ImageAndTextCell alloc] initImageCell: image];
                
                [cell setStringValue: [[NSString alloc] initWithUTF8String: entry->_name]];
                [cell setImage: image];
                
                return cell;
            }
            else
            {
                char *fullCPath = [entry genPath: entry->_parent forName: entry->_name];
                
                NSString *fullPath = [[NSString alloc] initWithUTF8String: fullCPath];
                
                NSImage *image = [_resmgr iconForFile: fullPath];
                
                ImageAndTextCell *cell = [[ImageAndTextCell alloc] initImageCell: image];
                
                [cell setStringValue: fullPath];
                
                [cell setImage: image];
                
                free(fullCPath);
                
                return cell;
            }
        }
            break;
            
        case kSizeColumn:
        {
            Entry      *entry = (Entry *)item;
            
            size_t size = entry->_size;
            
            NSString *name;
            if(size > (1024 * 1024 * 1024))
            {
                name = [[NSString alloc] initWithFormat: @"% 8.3f GB", (float)size / (1024.0 * 1024.0 * 1024.0)];
            }
            else if(size > (1024 * 1024))
            {
                name = [[NSString alloc] initWithFormat: @"% 8.3f MB", (float)size / (1024.0 * 1024.0)];
            }
            else if(size > 1024)
            {
                name = [[NSString alloc] initWithFormat: @"% 8.3f KB", (float)size / 1024.0];
            }
            else if(size)
            {
                name = [[NSString alloc] initWithFormat: @"%8.0f Bytes", (float)size];
            }
            else
            {
                name = @"";
            }
            
            TextCell *cell = [[TextCell alloc] initTextCell: name];
            
            return cell;
        }
            break;
            
        case kFileCountColumn:
        {
            size_t  count = 0;
            
            if([item isKindOfClass: [NSMutableArray class]])
            {
                NSMutableArray      *array = (NSMutableArray *)item;
                
                count = [array count];
            }
            else if([item isKindOfClass: [Entry class]])
            {
                Entry      *entry = (Entry *)item;
                
                if(entry->_type == DT_DIR)
                {
                    count = entry->_file_count;
                }
            }
            
            NSString *fileCount;
            
            if(count)
            {
                fileCount = [[NSString alloc] initWithFormat: @"%zu", count];
            }
            else
            {
                fileCount = @"";
            }
            
            TextCell *cell = [[TextCell alloc] initTextCell: fileCount];
            
            return cell;
        }
            break;
            
        default:
            break;
    }
    
    return NULL;
}

- (id) outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item
{
    if(tableColumn == NULL)
        return NULL;
        
    NSUInteger col_index = [[outlineView tableColumns] indexOfObject: tableColumn];
    switch(col_index)
    {
        case kSizeColumn:
        {
            Entry      *entry = (Entry *)item;
            
            size_t size = entry->_size;
            
            NSString *name;
            if(size > (1024 * 1024 * 1024))
            {
                name = [[NSString alloc] initWithFormat: @"% 8.2f GB", (float)size / (1024.0 * 1024.0 * 1024.0)];
            }
            else if(size > (1024 * 1024))
            {
                name = [[NSString alloc] initWithFormat: @"% 8.1f MB", (float)size / (1024.0 * 1024.0)];
            }
            else if(size > 1024)
            {
                name = [[NSString alloc] initWithFormat: @"% 8.0f KB", (float)size / 1024.0];
            }
            else if(size)
            {
                name = [[NSString alloc] initWithFormat: @"%8.0f Bytes", (float)size];
            }
            else
            {
                name = @"";
            }
            
            return name;
        }
            break;
            
        case kFileCountColumn:
        {
            size_t  count = 0;
            
            Entry      *entry = (Entry *)item;
            
            if(entry->_type == DT_DIR)
            {
                count = entry->_file_count;
            }
            
            NSString *fileCount;
            
            if(count)
            {
                fileCount = [[NSString alloc] initWithFormat: @"%zu", count];
            }
            else
            {
                fileCount = @"";
            }
            
            TextCell *cell = [[TextCell alloc] initTextCell: fileCount];
            
            return cell;
        }
            break;
            
        case kFileNameColumn:
            break;
    }
    
    return NULL;
}

- (void)outlineView:(NSOutlineView *)outlineView willDisplayCell:(NSCell*)cell forTableColumn:(NSTableColumn *)tableColumn item:(id)item
{
    // printf("%s tableColumn: %p item: %p\n", __FUNCTION__, tableColumn, item);
}

- (BOOL)outlineView:(NSOutlineView *)outlineView shouldEditTableColumn:(NSTableColumn *)tableColumn item:(id)item
{
    return FALSE;
}

- (void)outlineView:(NSOutlineView *)outlineView mouseDownInHeaderOfTableColumn:(NSTableColumn *)tableColumn
{
    int temp = _sortMode;
    
    if (tableColumn == [[outlineView tableColumns] objectAtIndex:kSizeColumn])
    {
        _sortMode = kSortSize;
    }
    else if (tableColumn == [[outlineView tableColumns] objectAtIndex:kFileNameColumn])
    {
        _sortMode = kSortFileName;
    }
    else if (tableColumn == [[outlineView tableColumns] objectAtIndex:kFileCountColumn])
    {
        _sortMode = kSortFileCount;
    }
    
    if(temp == _sortMode)
    {
        _sortDir *= -1;
    }
    
    [[_resmgr entries] sortEntries: [_resmgr entries] mode:_sortMode direction: _sortDir];
    
    [outlineView reloadData];
}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification;
{
    
}

@end
