//
//  TextCell.m
//  Wheres My Space?
//
//  Created by Michael Larson on 1/1/13.
//  Copyright (c) 2013 Sandstorm Software. All rights reserved.
//

#import "TextCell.h"

@implementation TextCell

- (id)init
{
	self = [super init];
	if (self)
    {
        // we want a smaller font
        [self setFont: [NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
        
        [self setAlignment: NSLeftTextAlignment];
        
        _attr = [[NSDictionary dictionaryWithObjectsAndKeys:
                  [self font], NSFontAttributeName,
                  [NSColor blackColor], NSForegroundColorAttributeName,
                  nil ] retain];
    }
	return self;
}


// -------------------------------------------------------------------------------
//	copyWithZone:zone
// -------------------------------------------------------------------------------
- (id)copyWithZone:(NSZone *)zone
{
    TextCell *cell = (TextCell*)[super copyWithZone:zone];

    return cell;
}

// -------------------------------------------------------------------------------

@end
