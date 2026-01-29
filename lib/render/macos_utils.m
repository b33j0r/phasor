#import <Cocoa/Cocoa.h>
#import <QuartzCore/CAMetalLayer.h>

void* createMetalLayer(void* ns_window_ptr) {
    NSWindow* window = (__bridge NSWindow*)ns_window_ptr;
    NSView* contentView = [window contentView];

    [contentView setWantsLayer:YES];
    CAMetalLayer* layer = [CAMetalLayer layer];
    [contentView setLayer:layer];

    return (__bridge void*)layer;
}
