
#import <Cocoa/Cocoa.h>

@interface ImageAndTextCell : NSImageCell
{
    NSImage         *image;
    NSString        *string;
    NSString        *_size;
    NSDictionary    *_attr;
}

@property (readwrite, strong) NSImage *image;

- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView;
- (NSSize)cellSize;
- (void)setStringValue:(NSString *)aString;

@end
