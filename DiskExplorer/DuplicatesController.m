//
//  DuplicatesController.m
//  DiskExplorer
//
//  Created by Michael Larson on 2/1/14.
//  Copyright (c) 2014 Sandstorm Software. All rights reserved.
//

#import "DuplicatesController.h"
#import "ImageAndTextCell.h"
#import "TextCell.h"
#import <mach/mach.h>
#import <mach/mach_time.h>

#undef get16bits
#if (defined(__GNUC__) && defined(__i386__)) || defined(__WATCOMC__) \
|| defined(_MSC_VER) || defined (__BORLANDC__) || defined (__TURBOC__)
#define get16bits(d) (*((const uint16_t *) (d)))
#endif

#if !defined (get16bits)
#define get16bits(d) ((((uint32_t)(((const uint8_t *)(d))[1])) << 8)\
+(uint32_t)(((const uint8_t *)(d))[0]) )
#endif

DuplicatesInfo gDuplicatesInfo;

static inline unsigned superFastHash (const char * data, size_t len)
{
    unsigned    hash = (int)len, tmp;
    int         rem;
    
    if (len <= 0 || data == NULL)
        return 0;
    
    rem = len & 3;
    len >>= 2;
    
    /* Main loop */
    for (;len > 0; len--)
    {
        hash  += get16bits (data);
        tmp    = (get16bits (data+2) << 11) ^ hash;
        hash   = (hash << 16) ^ tmp;
        data  += 2*sizeof (uint16_t);
        hash  += hash >> 11;
    }
    
    /* Handle end cases */
    switch (rem)
    {
        case 3: hash += get16bits (data);
            hash ^= hash << 16;
            hash ^= ((signed char)data[sizeof (uint16_t)]) << 18;
            hash += hash >> 11;
            break;
        case 2: hash += get16bits (data);
            hash ^= hash << 11;
            hash += hash >> 17;
            break;
        case 1: hash += (signed char)*data;
            hash ^= hash << 10;
            hash += hash >> 1;
    }
    
    /* Force "avalanching" of final 127 bits */
    hash ^= hash << 3;
    hash += hash >> 5;
    hash ^= hash << 4;
    hash += hash >> 17;
    hash ^= hash << 25;
    hash += hash >> 6;
    
    return hash;
}

static uint32_t coeffs[12] __attribute__((aligned(16))) = {
    /* Four carefully selected coefficients and interleaving zeros. */
    2561893793UL, 0, 1388747947UL, 0,
    3077216833UL, 0, 3427609723UL, 0,
    /* 128 bits of random data. */
    0x564A4447, 0xC7265595, 0xE20C241D, 0x128FA608,
};

#define COMBINE_AND_MIX(c_1, c_2, s_1, s_2, in)                              \
/* Phase 1: Perform four 32x32->64 bit multiplication with the             \
input block and words 1 and 3 coeffs, respectively.  This               \
effectively propagates a bit change in input to 32 more                 \
significant bit positions.  Combine into internal state by              \
subtracting the result of multiplications from the internal             \
state. */                                                               \
s_1 = _mm_sub_epi64(s_1, _mm_mul_epu32(c_1, _mm_unpackhi_epi32(in, in)));  \
s_2 = _mm_sub_epi64(s_2, _mm_mul_epu32(c_2, _mm_unpacklo_epi32(in, in)));  \
\
/* Phase 2: Perform shifts and xors to propagate the 32-bit                \
changes produced above into 64-bit (and even a little larger)           \
changes in the internal state. */                                       \
/* state ^= state >64> 29; */                                              \
s_1 = _mm_xor_si128(s_1, _mm_srli_epi64(s_1, 29));                         \
s_2 = _mm_xor_si128(s_2, _mm_srli_epi64(s_2, 29));                         \
/* state +64= state <64< 16; */                                            \
s_1 = _mm_add_epi64(s_1, _mm_slli_epi64(s_1, 16));                         \
s_2 = _mm_add_epi64(s_2, _mm_slli_epi64(s_2, 16));                         \
/* state ^= state >64> 21; */                                              \
s_1 = _mm_xor_si128(s_1, _mm_srli_epi64(s_1, 21));                         \
s_2 = _mm_xor_si128(s_2, _mm_srli_epi64(s_2, 21));                         \
/* state +64= state <128< 32; */                                           \
s_1 = _mm_add_epi64(s_1, _mm_slli_si128(s_1, 4));                          \
s_2 = _mm_add_epi64(s_2, _mm_slli_si128(s_2, 4));                          \
\
/* Phase 3: Propagate the changes among the four 64-bit words by           \
performing 64-bit subtractions and 32-bit word shuffling. */            \
s_1 = _mm_sub_epi64(s_1, s_2);                                             \
s_2 = _mm_sub_epi64(_mm_shuffle_epi32(s_2, _MM_SHUFFLE(0, 3, 2, 1)), s_1); \
s_1 = _mm_sub_epi64(_mm_shuffle_epi32(s_1, _MM_SHUFFLE(0, 1, 3, 2)), s_2); \
s_2 = _mm_sub_epi64(_mm_shuffle_epi32(s_2, _MM_SHUFFLE(2, 1, 0, 3)), s_1); \
s_1 = _mm_sub_epi64(_mm_shuffle_epi32(s_1, _MM_SHUFFLE(2, 1, 0, 3)), s_2); \
\
/* With good coefficients any one-bit flip in the input has now            \
changed all bits in the internal state with a probability               \
between 45% to 55%. */

static void hasshe2(const unsigned char *input_buf, size_t n_bytes,
                    unsigned char *output_state)
{
    __m128i coeffs_1, coeffs_2, rnd_data, input, state_1, state_2;
    
    coeffs_1 = _mm_load_si128((void *) coeffs);
    coeffs_2 = _mm_load_si128((void *) (coeffs + 4));
    rnd_data = _mm_load_si128((void *) (coeffs + 8));
    
    /* Initialize internal state to something random.  (Alternatively,
     if hashing a chain of data, read in the previous hash result from
     somewhere.) */
    state_1 = state_2 = rnd_data;
    
    while (n_bytes >= 16)
    {
        /* Read in 16 bytes, or 128 bits, from buf.  Advance buf and
         decrement n_bytes accordingly. */
        input = _mm_loadu_si128((void *) input_buf);
        input_buf += 16;
        n_bytes -= 16;
        
        COMBINE_AND_MIX(coeffs_1, coeffs_2, state_1, state_2, input);
    }
    
    /* Postprocessing.  Copy half of the internal state into fake input,
     replace it with the constant rnd_data, and do one combine and mix
     phase more. */
    input = state_1;
    state_1 = rnd_data;
    COMBINE_AND_MIX(coeffs_1, coeffs_2, state_1, state_2, input);
    
    _mm_storeu_si128((void *) output_state, state_1);
    _mm_storeu_si128((void *) (output_state + 16), state_2);
}

static inline char *genFullPath(char *path, char *name)
{
    size_t      len = strlen(path) + strlen(name) + 2;
    char        *fullPath = malloc(len);
    
    strcat(fullPath, path);
    
    char        *tail = &fullPath[strlen(fullPath)];
    *tail++ = '/';
    *tail = 0;
    
    strcat(tail, name);
    
    return fullPath;
}

@implementation DuplicatesController

-(id)initWithResourceMgr: (ResourceMgr *)mgr forView: (OutlineView *)outlineView;
{
    _resmgr = mgr;
    _duplicateView = outlineView;
    
    _hashTable = (HashEntry *)calloc(HASH_TABLE_SIZE, sizeof(HashEntry));
    _findDuplicatesComplete = 0;

    _sortMode = kSortSize;
    _sortDir = 1;

    gDuplicatesInfo._count = 0;
    gDuplicatesInfo._size = 0;
    
    [outlineView setDelegate: self];
    [outlineView setDataSource: self];

    return self;
}

-(bool)complete
{
    return _findDuplicatesComplete;
}

-(void)buildHashTable: (Entry *)entry
{
    for(int i=0; i<[entry->_entries count]; i++)
    {
        Entry *testEntry = (Entry *)[entry->_entries objectAtIndex: i];
        
        if(testEntry->_type == DT_DIR)
        {
            [self buildHashTable: testEntry];
        }
        else
        {
            unsigned hash;
            
            hash = testEntry->_size & HASH_TABLE_MASK;
            
            HashEntry   *hashEntry = (HashEntry *)malloc(sizeof(HashEntry));
            
            hashEntry->_entry    = testEntry;
            
            unsigned hashIndex = hash & HASH_TABLE_MASK;
            
            hashEntry->_next = _hashTable[hashIndex]._next;
            hashEntry->_prev = &_hashTable[hashIndex];
            
            _hashTable[hashIndex]._next->_prev = hashEntry;
            _hashTable[hashIndex]._next = hashEntry;
        }
    }
}

-(unsigned)countHashEntries:(HashEntry *)entry
{
    int count = 0;
    
    if(entry)
    {
        for(HashEntry *test=entry; test->_next != entry; test=test->_next)
        {
            count++;
        }
    }
    
    return count;
}

-(void) genFileSignature:(Entry *)entry
{
    char        buffer[256];
    char        *fullPath = genFullPath(entry->_parent->_path, entry->_name);
    
    FILE    *file = fopen(fullPath, "rb");
    if(file)
    {
        size_t len = entry->_size > 256 ? 256 : entry->_size;
        
        entry->_first_256_bytes_hash = (unsigned)superFastHash(buffer, len);
        
        fclose(file);
    }
    
    free(fullPath);
}

-(void) genFullFileSignature:(Entry *)entry
{
    unsigned char   *buffer;
    char            *fullPath = genFullPath(entry->_parent->_path, entry->_name);
    
    if(entry->_size)
    {
        size_t  buff_len = (entry->_size & ~0xf) + 16;
        
        buffer = (unsigned char *)malloc(buff_len);
        
        FILE    *file = fopen(fullPath, "rb");
        if(file)
        {
            fread(buffer, 1, entry->_size, file);
            
            hasshe2(buffer, buff_len, entry->_full_hash);
            
            entry->_full_hash_generated = 1;
            
            fclose(file);
        }
        
        free(buffer);
    }
    
    free(fullPath);
}

NSInteger compareDuplicateSize(id ptr1, id ptr2, void *context)
{
    NSUInteger  countA = [(NSMutableArray *)ptr1 count];
    NSUInteger  countB = [(NSMutableArray *)ptr1 count];
    Entry       *a = (Entry *)[(NSMutableArray *)ptr1 objectAtIndex: 0];
    Entry       *b = (Entry *)[(NSMutableArray *)ptr2 objectAtIndex: 0];
    int         dir = *(int *)context;
    
    if(countA * a->_size < countB * b->_size)
        return NSOrderedDescending * dir;
    else if(countA * a->_size == countB * b->_size)
        return NSOrderedSame * dir;
    
    return NSOrderedAscending * dir;
}

NSInteger compareDuplicateFileName(id ptr1, id ptr2, void *context)
{
    Entry       *a = (Entry *)[(NSMutableArray *)ptr1 objectAtIndex: 0];
    Entry       *b = (Entry *)[(NSMutableArray *)ptr2 objectAtIndex: 0];
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

NSInteger compareDuplicateFileCount(id ptr1, id ptr2, void *context)
{
    NSUInteger  countA = [(NSMutableArray *)ptr1 count];
    NSUInteger  countB = [(NSMutableArray *)ptr2 count];
    int         dir = *(int *)context;
    
    if(countA < countB)
        return NSOrderedDescending * dir;
    else if(countA == countB)
        return NSOrderedSame * dir;
    
    return NSOrderedAscending * dir;
}

-(bool)compareFileNames:(char *)src dest:(char *)dst
{
    while(*src && *dst)
    {
        if(*src == *dst)
        {
            src++;
            dst++;
            continue;
        }
        
        // spin src ptr past -<number> sequence
        else if((*src == '-') && (*dst == '.'))
        {
            src++;
            
            while(isnumber(*src))
            {
                src++;
            }
            
            continue;
        }
        // spin dst ptr past -<number> sequence
        else if((*dst == '-') && (*src == '.'))
        {
            dst++;
            
            while(isnumber(*dst))
            {
                dst++;
            }
            
            continue;
        }
        else
        {
            return false;
        }
    }
    
    return true;
}

- (void)sortDuplicates
{
    switch(_sortMode)
    {
        case kSortSize:
            [_duplicates sortUsingFunction: compareDuplicateSize context: &_sortDir];
            break;
            
        case kSortFileName:
            [_duplicates sortUsingFunction: compareDuplicateFileName context: &_sortDir];
            break;
            
        case kSortFileCount:
            [_duplicates sortUsingFunction: compareDuplicateFileCount context: &_sortDir];
            break;
    }
}

- (void)alertDidEnd:(NSAlert *)alert returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo
{
    // user pressed ok
    if(returnCode == NSAlertFirstButtonReturn)
    {
        _continueTesting = false;
    }
    else if(returnCode == NSAlertFirstButtonReturn)
    {
        _continueTesting = true;
    }
    
    _alertDone = true;
}

- (size_t)countEntries:(Entry *)parent UnderSize:(size_t)size
{
    size_t  count = 0;
    
    for(Entry *entry in parent->_entries)
    {
        if(entry->_type == DT_DIR)
        {
            count += [self countEntries: entry UnderSize: size];
        }
        else
        {
            if(entry->_size <= size)
            {
                count++;
            }
        }
    }
                     
    return count;
}

#define MIN_SIZE    (0x1 << 13)

- (void)runAlert
{
    size_t count = [self countEntries: [_resmgr entries] UnderSize: MIN_SIZE];
    
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    [alert addButtonWithTitle:@"Done"];
    [alert addButtonWithTitle:@"Keep Searching"];
    
    NSString *info = [[NSString alloc] initWithFormat: @"All duplicate files of greather than 16K Bytes in size have been found, do you want to continue? %zu files need to be compared.. this can take a long time and not save signficatant space", count];
                                                                                                                                                                                                                                                    
    [alert setMessageText: info];
    [alert setAlertStyle:NSWarningAlertStyle];
    [alert beginSheetModalForWindow:[_duplicateView window] modalDelegate:self didEndSelector:@selector(alertDidEnd:returnCode:contextInfo:) contextInfo: NULL];
    
    [info release];
}

-(void)setHeaderTitles:(NSOutlineView *)outlineView
{
    NSInteger count = [outlineView numberOfColumns];
    
    for(int i=0; i<count; i++)
    {
        NSTableColumn *column = [[outlineView tableColumns] objectAtIndex:i];
        
        NSString *analyzeTitles[] = {@"Name", @"Size", @"Files"};
        
        [[column headerCell] setTitle: analyzeTitles[i]];
    }
}

- (void) reloadDirectoryView: (id) item
{
    [_duplicateView reloadData];
    [_duplicateView display];
}

-(void)findDuplicatesThread:(id)ptr
{
    gDuplicatesInfo._count = 0;
    gDuplicatesInfo._size = 0;
    
    for(int i=0; i<HASH_TABLE_SIZE; i++)
    {
        _hashTable[i]._next = &_hashTable[i];
        _hashTable[i]._prev = &_hashTable[i];
    }
    
    if(ptr == NULL)
    {
        [self buildHashTable: [_resmgr entries]];
    }
    else
    {
        NSMutableArray  *array = ptr;
        
        for(int i=0; i<[array count]; i++)
        {
            [self buildHashTable: [array objectAtIndex: i]];
        }
    }
    
    if(_duplicates == NULL)
    {
        _duplicates = [[NSMutableArray alloc] init];
    }
    else
    {
        [_duplicates removeAllObjects];
    }
    
    dispatch_group_t group = dispatch_group_create();
    dispatch_queue_t queue = dispatch_queue_create("findDuplicatesQueue", NULL);
    
    bool gaveSmallSizeTestNotice = false;
    
    _continueTesting = true;
    for(size_t minCompareSize=(0x1 << 27); minCompareSize && (_continueTesting == true); minCompareSize >>= 1)
    {
        if((gaveSmallSizeTestNotice == false) && (minCompareSize <= MIN_SIZE))
        {
            dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
            
            _alertDone = false;
            gaveSmallSizeTestNotice = true;
            
            [self performSelectorOnMainThread: @selector(runAlert) withObject: nil waitUntilDone: YES];
            
            while(_alertDone == false)
                sleep(1);
            
            if(_continueTesting == false)
            {
                continue;
            }
        }
        
        for(int i=0; i<HASH_TABLE_SIZE; i++)
        {
            if(_hashTable[i]._next == &_hashTable[i])
                continue;
            
            if(_hashTable[i]._next->_entry && _hashTable[i]._next->_entry->_size < minCompareSize)
                continue;
            
            dispatch_block_t findDuplicatesInHashTableBlock = ^{
                HashEntry *src = _hashTable[i]._next;
                
                // cycle through all entries in hash table row
                while(src != &_hashTable[i])
                {
                    NSMutableArray *srcDuplicates = NULL;
                    
                    Entry *srcEntry = src->_entry;
                    
                    if(srcEntry->_size < minCompareSize)
                    {
                        src = src->_next;
                        continue;
                    }
                    
                    // marked duplicate don't test for more dups
                    if(srcEntry->_duplicate)
                    {
                        src = src->_next;
                        continue;
                    }
                    
                    // forward search through hash table for dups
                    HashEntry *test = src->_next;
                    while(test != &_hashTable[i])
                    {
                        Entry   *testEntry = test->_entry;
                        
                        // skip dups
                        if(testEntry->_duplicate)
                        {
                            test = test->_next;
                            continue;
                        }
                        
                        // size test
                        if(srcEntry->_size != testEntry->_size)
                        {
                            test = test->_next;
                            continue;
                        }
                        
                        // compare file names
                        if([self compareFileNames: srcEntry->_name dest: testEntry->_name] == false)
                        {
                            test = test->_next;
                            continue;
                        }
                        
                        // deferred hash gen
                        if(srcEntry->_first_256_bytes_hash == 0)
                            [self genFileSignature: srcEntry];
                        
                        // deferred hash gen
                        if(testEntry->_first_256_bytes_hash == 0)
                            [self genFileSignature: testEntry];
                        
                        // test first 256 bytes
                        if(srcEntry->_first_256_bytes_hash == testEntry->_first_256_bytes_hash)
                        {
                            // deferred full hash gen on src
                            if(srcEntry->_full_hash_generated == 0)
                                [self genFullFileSignature: srcEntry ];
                            
                            // deferred full hash gen on test
                            if(testEntry->_full_hash_generated == 0)
                                [self genFullFileSignature: testEntry ];
                            
                            // compare full hash
                            if(!memcmp(srcEntry->_full_hash, testEntry->_full_hash, sizeof(srcEntry->_full_hash)))
                            {
                                // deferred duplicates allocation
                                if(srcEntry->_duplicate == 0)
                                {
                                    srcEntry->_duplicate = 1;
                                    
                                    srcDuplicates = [[NSMutableArray alloc] init];
                                    [srcDuplicates addObject: srcEntry];
                                }
                                
                                // add duplicate to the array
                                testEntry->_duplicate    = 1;
                                [srcDuplicates addObject: testEntry];
                                
                                OSAtomicAdd64(1, &gDuplicatesInfo._count);
                                OSAtomicAdd64(testEntry->_size, &gDuplicatesInfo._size);
                            }
                        }

                        test = test->_next;
                    }
                    
                    // add duplicates to top level duplicates list
                    if(srcDuplicates)
                    {
                        OSSpinLockCall(_lock, [_duplicates addObject: srcDuplicates]);
                        srcDuplicates = NULL;
                    }
                    
                    src = src->_next;
                    
                }
                
                if(_update)
                {
                    _update--;
                    [self performSelectorOnMainThread: @selector(reloadDirectoryView:) withObject: _duplicateView waitUntilDone: YES];
                }
            };
            
            dispatch_group_async(group, queue, findDuplicatesInHashTableBlock);
        }
    }
    
    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
    
    dispatch_release(group);
    dispatch_release(queue);
    
    [self performSelectorOnMainThread: @selector(reloadDirectoryView:) withObject: _duplicateView waitUntilDone: YES];
    
    [_timer invalidate];
    
    _timer = NULL;
    
    _findDuplicatesComplete = 1;
    _threadRunning = 0;
}

-(void)freeHashTable
{
    for(int i=0; i<HASH_TABLE_SIZE; i++)
    {
        if(_hashTable[i]._next == &_hashTable[i])
            continue;
        
        HashEntry   *elem = _hashTable[i]._next;
        
        while(elem && (elem != &_hashTable[i]))
        {
            _hashTable[i]._next = elem->_next;
            
            free(elem);
            
            elem = _hashTable[i]._next;
        }
    }
}

- (void) updateTimer: (NSTimer *)timer
{
    _update++;
}

-(void)findDuplicates: (id)sender
{
    if((_findDuplicatesComplete == 0) && (_threadRunning == 0))
    {
        _threadRunning = 1;
        [_duplicateView display];
        
        NSIndexSet      *selectedRows = [_duplicateView selectedRowIndexes];
        
        if([selectedRows count] > 0)
        {
            NSMutableArray  *directoryEntries = [[NSMutableArray alloc] init];
            
            for(NSUInteger i=[selectedRows firstIndex]; i<=[selectedRows lastIndex]; i++)
            {
                if([selectedRows containsIndex: i] == 0)
                    continue;
                
                [directoryEntries addObject: [_duplicateView itemAtRow: i]];
            }
            
            [NSThread detachNewThreadSelector: @selector(findDuplicatesThread:) toTarget: self withObject: directoryEntries];
        }
        else
        {
            [NSThread detachNewThreadSelector: @selector(findDuplicatesThread:) toTarget: self withObject: NULL];
        }
        
        _timer = [NSTimer scheduledTimerWithTimeInterval: 1.0f / 5.0f target: self selector: @selector(updateTimer:) userInfo: NULL repeats: YES];
    }
}

#pragma mark OutlineView delegate methods

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item
{
    [self sortDuplicates];
    
    if(item == NULL)
    {
        return [_duplicates count];
    }
    else if([item isKindOfClass: [NSMutableArray class]])
    {
        NSMutableArray *array = (NSMutableArray *)item;
        
        return [array count];
    }
    
    return 0;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item
{
    if(item == NULL)
    {
        return false;
    }
    else if([item isKindOfClass: [NSMutableArray class]])
    {
        NSMutableArray   *array = (NSMutableArray *)item;
        
        return [array count] > 0;
    }
    
    return 0;
}

- (id) outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item
{
    if(item == NULL)
    {
        return [_duplicates objectAtIndex: index];
    }
    else if([item isKindOfClass: [NSMutableArray class]])
    {
        NSMutableArray   *array = (NSMutableArray *)item;
        
        return [array objectAtIndex: index];
    }
    
    return NULL;
}

- (NSCell *)outlineView:(NSOutlineView *)outlineView dataCellForTableColumn:(NSTableColumn *)tableColumn item:(id)item
{
    bool showPath = true;
    
    if(tableColumn == NULL)
        return NULL;
    
    NSUInteger col_index = [[outlineView tableColumns] indexOfObject: tableColumn];
    switch(col_index)
    {
        case kFileNameColumn:
            if([item isKindOfClass: [NSMutableArray class]])
            {
                NSMutableArray      *array = (NSMutableArray *)item;
                
                item = [array objectAtIndex: 0];
                
                showPath = false;

                if([item isKindOfClass: [NSMutableArray class]])
                {
                    NSMutableArray      *array = (NSMutableArray *)item;
                    
                    item = [array objectAtIndex: 0];
                    
                    showPath = true;
                }
            }
            else if([item isKindOfClass: [Entry class]])
            {
                item = (Entry *)item;
            }
            break;
            
        case kSizeColumn:
            break;

        case kFileCountColumn:
            break;
    }
    
    switch(col_index)
    {
        case kFileNameColumn:
        {
            Entry   *entry = (Entry *)item;
            char    *fullCPath;
            
            fullCPath = [entry genPath: entry->_parent forName: entry->_name];
            
            NSString *fullPath = [[NSString alloc] initWithUTF8String: fullCPath];
            
            NSImage *image = [_resmgr iconForFile: fullPath];
            
            ImageAndTextCell *cell = [[ImageAndTextCell alloc] initImageCell: image];
            
            if(showPath)
            {
                [cell setStringValue: fullPath];
            }
            else
            {
                [fullPath release];
                
                NSString *fullPath = [[NSString alloc] initWithUTF8String: entry->_name];
                [cell setStringValue: fullPath];
            }
            
            [cell setImage: image];
            
            free(fullCPath);
            
            return cell;
        }
            break;
            
        case kSizeColumn:
        {
            size_t size = 0;
            
            if([item isKindOfClass: [NSMutableArray class]])
            {
                NSMutableArray      *array = (NSMutableArray *)item;
                size_t  count = 0;
                
                count = [array count];
                
                Entry *entry = [array objectAtIndex: 0];
                
                size = entry->_size * count;
            }
            else if([item isKindOfClass: [Entry class]])
            {
                Entry      *entry = (Entry *)item;
                
                size = entry->_size;
            }
            
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
    bool showPath = true;
    
    NSUInteger col_index = [[outlineView tableColumns] indexOfObject: tableColumn];
    switch(col_index)
    {
        case kFileNameColumn:
            return NULL;
            break;
            
        case kSizeColumn:
            if([item isKindOfClass: [NSMutableArray class]])
            {
                NSMutableArray      *array = (NSMutableArray *)item;
                
                item = [array objectAtIndex: 0];
                
                showPath = false;

                if([item isKindOfClass: [NSMutableArray class]])
                {
                    NSMutableArray      *array = (NSMutableArray *)item;
                    
                    item = [array objectAtIndex: 0];
                    
                    showPath = true;
                }
            }
            else if([item isKindOfClass: [Entry class]])
            {
                item = (Entry *)item;
            }
            break;
            
        case kFileCountColumn:
            break;
    }
    
    switch(col_index)
    {
        case kFileNameColumn:
        {
            Entry      *entry = (Entry *)item;
            
            char *fullCPath;
            
            fullCPath = [entry genPath: entry->_parent forName: entry->_name];
            
            NSString *fullPath = [[NSString alloc] initWithUTF8String: fullCPath];
            
            NSImage *image = [_resmgr iconForFile: fullPath];
            
            ImageAndTextCell *cell = [[ImageAndTextCell alloc] initImageCell: image];
            
            if(showPath)
            {
                [cell setStringValue: fullPath];
            }
            else
            {
                [fullPath release];
                
                NSString *fullPath = [[NSString alloc] initWithUTF8String: entry->_name];
                [cell setStringValue: fullPath];
            }
            
            [cell setImage: image];
            
            free(fullCPath);
            
            return cell;
        }
            break;
            
        case kSizeColumn:
        {
            size_t size = 0;
            
            if([item isKindOfClass: [NSMutableArray class]])
            {
                NSMutableArray      *array = (NSMutableArray *)item;
                size_t  count = 0;
                
                count = [array count];
                
                Entry *entry = [array objectAtIndex: 0];
                
                size = entry->_size * count;
            }
            else if([item isKindOfClass: [Entry class]])
            {
                Entry      *entry = (Entry *)item;
                
                size = entry->_size;
            }
            
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
            
            if([item isKindOfClass: [NSMutableArray class]])
            {
                if(col_index == kFileCountColumn)
                {
                    NSMutableArray      *array = (NSMutableArray *)item;
                    
                    count = [array count];
                }
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
    }
    
    return NULL;
}

- (void)outlineView:(NSOutlineView *)outlineView willDisplayCell:(NSCell*)cell forTableColumn:(NSTableColumn *)tableColumn item:(id)item
{
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
    
    [self sortDuplicates];
    
    [outlineView reloadData];
}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification;
{
    
}

@end
