//
//  TextCell.h
//  Wheres My Space?
//
//  Created by Michael Larson on 1/1/13.
//  Copyright (c) 2013 Sandstorm Software. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface TextCell : NSTextFieldCell
{
    NSDictionary    *_attr;
}

- (id)copyWithZone:(NSZone *)zone;

@end
