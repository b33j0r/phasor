#import <Cocoa/Cocoa.h>
#import <QuartzCore/CAMetalLayer.h>

void setMetalLayerDisplaySync(void* layer_ptr, int vsync);

void* createMetalLayerWithVsync(void* ns_window_ptr, int vsync) {
    NSWindow* window = (__bridge NSWindow*)ns_window_ptr;
    NSView* contentView = [window contentView];

    [contentView setWantsLayer:YES];
    CAMetalLayer* layer = [CAMetalLayer layer];
    setMetalLayerDisplaySync((__bridge void*)layer, vsync);
    [contentView setLayer:layer];

    return (__bridge void*)layer;
}

void* createMetalLayer(void* ns_window_ptr) {
    return createMetalLayerWithVsync(ns_window_ptr, 1);
}

void setMetalLayerDisplaySync(void* layer_ptr, int vsync) {
    CAMetalLayer* layer = (__bridge CAMetalLayer*)layer_ptr;
    if ([layer respondsToSelector:@selector(setDisplaySyncEnabled:)]) {
        layer.displaySyncEnabled = (vsync != 0);
    }
}
