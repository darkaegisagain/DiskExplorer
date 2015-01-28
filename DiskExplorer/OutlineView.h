//
//  OutlineView.h
//  DiskExplorer
//
//  Created by Michael Larson on 1/13/14.
//  Copyright (c) 2014 Sandstorm Software. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "Entry.h"

#define COLUMN_WIDTH        96

enum {
    kOpenFile,
    kShowFile,
    kMoveFileToTrash,
    kMoveFileToTrashNoQuestions,
    kExpandSelection,
    kCollapseSelection,
};

enum {
    kFileNameColumn,
    kSizeColumn,
    kFileCountColumn,
};

typedef struct SelectedItem_t {
    struct SelectedItem_t   *next;
    id                      item;
} SelectedItem;

@interface OutlineView : NSOutlineView
{
    SelectedItem    *_selectedItems;
    unsigned        _ctrlKeyMouseDown;
    NSURL           *loggingURL;
    FILE            *loggingFP;

@public
    Entry           *_entries;
}

- (void)alertDidEnd:(NSAlert *)alert returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo;

@end
