//
//  OutlineView.m
//  DiskExplorer
//
//  Created by Michael Larson on 1/13/14.
//  Copyright (c) 2014 Sandstorm Software. All rights reserved.
//

#import "OutlineView.h"

@implementation OutlineView

typedef struct ParentItem_t {
    struct ParentItem_t   *_next;
    id                    _parent;
    id                    _item;
} ParentItem;

ParentItem *newParentItem(void)
{
    return (ParentItem *)calloc(1, sizeof(ParentItem));
}

typedef struct TreeViewState_t {
    struct TreeViewState_t  *_prev, *_next;
    id                      _parent;
    id                      _item;
    struct TreeViewState_t  *_directory;
} TreeViewState;

- (id)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        // Initialization code here.
    }
    return self;
}

- (void)drawRect:(NSRect)dirtyRect
{
	[super drawRect:dirtyRect];
	
    // Drawing code here.
}

- (BOOL)acceptsFirstResponder
{
    return TRUE;
}

- (BOOL)becomeFirstResponder
{
    return TRUE;
}

- (void)getTreeViewState:(TreeViewState *)state forItem: (id)item
{
    if([self isExpandable: item])
    {
        if([self isItemExpanded: item] == FALSE)
            return;
        
        NSInteger   numItems = [[NSApp delegate] outlineView: self numberOfChildrenOfItem: item];
        
        if(numItems == 0)
            return;
        
        state->_directory = (TreeViewState *)calloc(1, sizeof(TreeViewState));
        
        state = state->_directory;
        
        state->_parent = [self parentForItem: item];
        state->_item = item;
        
        state->_next = state;
        state->_prev = state;
        
        for(NSInteger i=0; i<numItems; i++)
        {
            TreeViewState *newState = calloc(1, sizeof(TreeViewState));
            
            newState->_parent = item;
            newState->_item = [[NSApp delegate] outlineView: self child: i ofItem: item];
            
            newState->_next = state;
            newState->_prev = state->_prev;
            
            state->_prev->_next = newState;
            state->_prev = newState;
            
            [self getTreeViewState: newState forItem: newState->_item];
        }
    }
}

- (void)alertDidEnd:(NSAlert *)alert returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo
{
    // user pressed ok
    if(returnCode == NSAlertFirstButtonReturn)
    {
        NSIndexSet      *selectedRows = [self selectedRowIndexes];
        NSMutableArray  *URLs = [NSMutableArray array];
        
        _ctrlKeyMouseDown = 0;
        
        TreeViewState head;
        
        head._parent = NULL;
        head._item = NULL;
        head._directory = NULL;
        head._next = &head;
        head._prev = &head;
        
        for(NSInteger i=0; i<[self numberOfRows]; i++)
        {
            TreeViewState *state = calloc(1, sizeof(TreeViewState));
            
            state->_parent = NULL;
            state->_item = [self itemAtRow: i];
            
            state->_next = &head;
            state->_prev = head._prev;
            
            head._prev->_next = state;
            head._prev = state;
            
            [self getTreeViewState: state forItem: state->_item];
        }
        
        ParentItem  *piList = NULL;
        for(NSInteger i=[selectedRows firstIndex]; i<=[selectedRows lastIndex]; i++)
        {
            if([selectedRows containsIndex: i] == 0)
                continue;
            
            id item = [self itemAtRow: i];
            id parent = [self parentForItem: item];
            
            ParentItem  *elem = newParentItem();
            
            elem->_parent = parent;
            elem->_item = item;
            elem->_next = piList;
            
            piList = elem;
        }
        
        // remove entries from parent
        ParentItem  *piElem = piList;
        while(piElem)
        {
            Entry      *entry = (Entry *)piElem->_item;
                        
            if(entry->_type == DT_DIR)
            {
                NSURL *url;
                
                char *path = [entry genFullPath];
                
                NSString *fullPath = [[NSString alloc] initWithUTF8String: path];
                
                url = [NSURL fileURLWithPath: fullPath isDirectory: (entry->_type == DT_DIR)];
                
                [fullPath autorelease];
                
                [URLs addObject: url];
                
                if(loggingFP)
                {
                    fprintf(loggingFP, "Move %s to trash\n", path);
                }
                
                free(path);
            }
            else
            {
                NSURL *url;
                
                char *fullCPath = [entry genFullPath];
                
                NSString *fullPath = [[NSString alloc] initWithUTF8String: fullCPath];
                
                url = [NSURL fileURLWithPath: fullPath isDirectory: (entry->_type == DT_DIR)];
                
                [fullPath autorelease];
                
                if(loggingFP)
                {
                    fprintf(loggingFP, "Move %s to trash\n", fullCPath);
                }
                
                free(fullCPath);
                
                [URLs addObject: url];
            }
            
            [entry->_parent->_entries removeObject: entry];
            
            piElem = piElem->_next;
        }

        // free allocated piElem's
        piElem = piList;
        while(piElem)
        {
            ParentItem *next = piElem->_next;
            free(piElem);
            
            piElem = next;
        }
        
        [self deselectAll: self];
        
        [self noteNumberOfRowsChanged];
        [self reloadData];
        
        //        [[NSWorkspace sharedWorkspace] recycleURLs: URLs completionHandler: nil];
    }
}

- (void)performOp: (unsigned) op
{
    NSMutableArray  *URLs = [NSMutableArray array];
    NSIndexSet      *selectedRows = [self selectedRowIndexes];
    id              parent = NULL;
    unsigned        hasDirectoriesSelected = 0;
    
    for(NSUInteger i=[selectedRows firstIndex]; i<=[selectedRows lastIndex]; i++)
    {
        if([selectedRows containsIndex: i] == 0)
            continue;
        
        Entry      *entry = (Entry *)[self itemAtRow: i];
        
        switch(op)
        {
            case kOpenFile:
            {
                char *fullCPath = [entry genFullPath];
                
                NSString *fullPath = [[NSString alloc] initWithUTF8String: fullCPath];
                
                [[NSWorkspace sharedWorkspace] openFile: fullPath];
                
                [fullPath autorelease];
                
                free(fullCPath);
            }
                break;
                
            case kShowFile:
            {
                char *fullCPath = [entry genFullPath];
                char *fullParentCPath = [entry->_parent genFullPath];
                
                NSString *fullPath = [[NSString alloc] initWithUTF8String: fullCPath];
                NSString *path = [[NSString alloc] initWithUTF8String: fullParentCPath];
                
                free(fullCPath);
                
                [URLs addObject: [NSURL fileURLWithPath: fullPath isDirectory: (entry->_type == DT_DIR)]];
                
                [fullPath release];
                [path release];
            }
                break;
                
            case kMoveFileToTrash:
            case kMoveFileToTrashNoQuestions:
            {
                if(entry->_type == DT_DIR)
                {
                    hasDirectoriesSelected = 1;
                }
            }
                break;
                
            case kExpandSelection:
//                [self expandItem: entry->item expandChildren: TRUE];
                break;
                
            case kCollapseSelection:
//                [self collapseItem: entry->item collapseChildren: TRUE];
                break;
                
            default:
                break;
        }
        
        if (op != kMoveFileToTrash && [self parentForItem: [self itemAtRow: i]] != parent)
        {
            if(parent)
                [self reloadItem: parent reloadChildren: YES];
            
            parent = [self parentForItem: [self itemAtRow: i]];
        }
    }
    
    switch(op)
    {
        case kMoveFileToTrashNoQuestions:
            [self alertDidEnd: NULL returnCode: NSAlertFirstButtonReturn contextInfo: NULL];
            break;
            
        case kMoveFileToTrash:
        {
            NSAlert *alert = [[[NSAlert alloc] init] autorelease];
            [alert addButtonWithTitle:@"OK"];
            [alert addButtonWithTitle:@"Cancel"];
            [alert setMessageText:@"Move selected items to Trash?"];
            if(hasDirectoriesSelected)
            {
                [alert setInformativeText:@"Selected items contain folders"];
            }
            [alert setAlertStyle:NSWarningAlertStyle];
            [alert beginSheetModalForWindow:[self window] modalDelegate:self didEndSelector:@selector(alertDidEnd:returnCode:contextInfo:) contextInfo: NULL];
        }
            break;
            
        case kShowFile:
        {
            [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs: URLs];
        }
            break;
            
        default:
            break;
    }
}

- (void)openFile: (NSEvent *)theEvent
{
    [self performOp: kOpenFile];
}

- (void)showInFinder: (NSEvent *)theEvent
{
    [self performOp: kShowFile];
}

- (void)moveToTrash: (NSEvent *)theEvent
{
    if (([theEvent modifierFlags] & NSCommandKeyMask) &&
        ([theEvent modifierFlags] & NSAlternateKeyMask))
    {
        [self performOp: kMoveFileToTrashNoQuestions];
    }
    else
    {
        [self performOp: kMoveFileToTrash];
    }
}

- (void)expandSelection: (NSEvent *)theEvent
{
    [self performOp: kExpandSelection];
}

- (void)collapseSelection: (NSEvent *)theEvent
{
    [self performOp: kCollapseSelection];
}

- (void)keyDown:(NSEvent *)theEvent
{
    unsigned short keyCode = [theEvent keyCode];
    
    switch(keyCode)
    {
        case 3:
            if ([theEvent modifierFlags] & NSCommandKeyMask)
            {
                [self showInFinder: theEvent];
            }
            break;
            
        case 31:
            if ([theEvent modifierFlags] & NSCommandKeyMask)
            {
                [self openFile: theEvent];
            }
            break;
            
        case 15:
            [self reloadItem: NULL reloadChildren: YES];
            break;
            
        case 51:
            if ([theEvent modifierFlags] & NSCommandKeyMask)
            {
//                if([[NSApp delegate] isExpertMode])
                {
                    [self moveToTrash: theEvent];
                }
            }
            break;
            
        case 123:
            if ([theEvent modifierFlags] & NSCommandKeyMask)
            {
                [self collapseSelection:theEvent];
            }
            break;
            
        case 124:
            if ([theEvent modifierFlags] & NSCommandKeyMask)
            {
                [self expandSelection:theEvent];
            }
            break;
            
    }
    
    [super keyDown: theEvent];
}

- (void)keyUp:(NSEvent *)theEvent
{
    
}

- (int)selectedCount: (SelectedItem *)list
{
    unsigned count = 0;
    
    while(list)
    {
        count++;
        
        list = list->next;
    }
    
    return count;
}

- (void)mouseDown:(NSEvent *)theEvent
{
    [super mouseDown:theEvent];
    
    if ([theEvent modifierFlags] & NSControlKeyMask)
    {
        NSMenu      *menu = [[NSMenu alloc] initWithTitle:@"File Menu"];
        NSMenuItem  *menuItem;
        
        _ctrlKeyMouseDown = 1;
        
        [menu setAutoenablesItems:NO];
        
        menuItem = [menu addItemWithTitle:@"Show in Finder"
                                   action:@selector(showInFinder:)
                            keyEquivalent:@"f"];
        
        [menuItem setKeyEquivalentModifierMask: NSCommandKeyMask];
        
        menuItem = [menu addItemWithTitle:@"Open"
                                   action:@selector(openFile:)
                            keyEquivalent:@"o"];
        
        [menuItem setKeyEquivalentModifierMask: NSCommandKeyMask];
        
//        if([[NSApp delegate] isExpertMode])
        {
            [menu addItem: [NSMenuItem separatorItem]];
            
            menuItem = [menu addItemWithTitle:@"Move to Trash"
                                       action:@selector(moveToTrash:)
                                keyEquivalent:@""];
        }
        
        [NSMenu popUpContextMenu:menu withEvent: theEvent forView: self];
    }
    else
    {
        _ctrlKeyMouseDown = 0;
    }
}

- (void)rightMouseDown:(NSEvent *)theEvent
{
    [super rightMouseDown:theEvent];
}

- (void)otherMouseDown:(NSEvent *)theEvent
{
    [super otherMouseDown:theEvent];
}

- (void)mouseUp:(NSEvent *)theEvent
{
    [super mouseUp:theEvent];
}

- (void)rightMouseUp:(NSEvent *)theEvent
{
    [super rightMouseUp:theEvent];
}

- (void)otherMouseUp:(NSEvent *)theEvent
{
    [super otherMouseUp:theEvent];
}

@end
