#import <Cocoa/Cocoa.h>
#import <QuartzCore/CAMetalLayer.h>

void* createMetalLayerWithVsync(void* ns_window_ptr, int vsync) {
    NSWindow* window = (__bridge NSWindow*)ns_window_ptr;
    NSView* contentView = [window contentView];

    [contentView setWantsLayer:YES];
    CAMetalLayer* layer = [CAMetalLayer layer];
    if ([layer respondsToSelector:@selector(setDisplaySyncEnabled:)]) {
        layer.displaySyncEnabled = (vsync != 0);
    }
    [contentView setLayer:layer];

    return (__bridge void*)layer;
}

void* createMetalLayer(void* ns_window_ptr) {
    return createMetalLayerWithVsync(ns_window_ptr, 1);
}
