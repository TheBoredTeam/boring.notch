// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Harsh Vardhan Goswami (@theboringhumane).
// Attribution applies to the extension platform contributions.

// Standalone native ABI fixture. Each image gets unique Objective-C class names.
#import <AppKit/AppKit.h>
#include <fcntl.h>
#include <math.h>
#include <unistd.h>
#include "../../docs/extension-api.h"

#ifndef BN_PROVIDER_INDEX
#error Build this fixture with build.py.
#endif
#define BN_JOIN_INNER(a, b) a##b
#define BN_JOIN(a, b) BN_JOIN_INNER(a, b)
#define BNState BN_JOIN(BNStressState_, BN_PROVIDER_TOKEN)
#define BNProbeController BN_JOIN(BNStressController_, BN_PROVIDER_TOKEN)
#define BNSettingsController BN_JOIN(BNStressSettings_, BN_PROVIDER_TOKEN)

static NSString *BNProviderID(void) { return @BN_PROVIDER_ID; }
static NSInteger BNFirstTab(void) { return (BN_PROVIDER_INDEX - 1) * 8 + 1; }
static NSString *BNTabID(NSInteger number) { return [NSString stringWithFormat:@"probe-%03ld", (long)number]; }
static NSString *BNTabTitle(NSInteger number) { return [NSString stringWithFormat:@"Probe %03ld", (long)number]; }

static void BNLog(NSString *event, NSDictionary *fields) {
    @autoreleasepool {
        const char *configured = getenv("BN_TAB_STRESS_LOG");
        if (configured && !*configured) return;
        NSString *path = configured ? [NSString stringWithUTF8String:configured] : @"/tmp/boring-tab-scale/controllers.jsonl";
        if (!path) return;
        NSMutableDictionary *record = [fields mutableCopy] ?: [NSMutableDictionary dictionary];
        record[@"event"] = event;
        record[@"providerID"] = BNProviderID();
        record[@"pid"] = @(getpid());
        record[@"timestamp"] = @([NSDate date].timeIntervalSince1970);
        NSData *json = [NSJSONSerialization dataWithJSONObject:record options:NSJSONWritingSortedKeys error:nil];
        if (!json) return;
        NSMutableData *line = [json mutableCopy];
        [line appendBytes:"\n" length:1];
        [[NSFileManager defaultManager] createDirectoryAtPath:path.stringByDeletingLastPathComponent
                                 withIntermediateDirectories:YES attributes:nil error:nil];
        int file = open(path.fileSystemRepresentation, O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC, 0600);
        if (file < 0) return;
        // One append per event keeps records intact across fixture instances.
        (void)write(file, line.bytes, line.length);
        close(file);
    }
}

@class BNSettingsController;
@interface BNState : NSObject
@property(nonatomic) BOOL active;
@property(nonatomic) BOOL tabsVisible;
@property(nonatomic) void *context;
@property(nonatomic) BNExtensionCommand command;
@property(nonatomic, strong) NSMutableData *snapshot;
@property(nonatomic, strong) BNSettingsController *settings;
- (void)setTabsVisibleAndPublish:(BOOL)visible;
- (const char *)tabsJSON;
- (void)stop;
@end

@interface BNProbeController : NSViewController
@property(nonatomic, copy) NSDictionary *record;
- (instancetype)initWithTab:(NSInteger)number context:(NSDictionary *)context;
@end

@implementation BNProbeController
- (instancetype)initWithTab:(NSInteger)number context:(NSDictionary *)context {
    if (!(self = [super initWithNibName:nil bundle:nil])) return nil;
    _record = @{@"controllerID":NSUUID.UUID.UUIDString, @"tabID":BNTabID(number),
                @"title":BNTabTitle(number), @"presentation":context[@"presentation"],
                @"displayID":context[@"displayID"] ?: NSNull.null, @"contentSize":context[@"contentSize"],
                @"controllerClass":NSStringFromClass(self.class)};
    NSSize size = NSMakeSize([context[@"contentSize"][@"width"] doubleValue],
                            [context[@"contentSize"][@"height"] doubleValue]);
    self.preferredContentSize = size;
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, size.width, size.height)];
    self.view.identifier = [NSString stringWithFormat:@"%@.%@", BNProviderID(), BNTabID(number)];
    NSTextField *title = [NSTextField labelWithString:BNTabTitle(number)];
    title.font = [NSFont systemFontOfSize:24 weight:NSFontWeightSemibold];
    title.textColor = NSColor.whiteColor;
    NSTextField *detail = [NSTextField labelWithString:[NSString stringWithFormat:@"%@ · %.0f × %.0f pt",
                                                     context[@"presentation"], size.width, size.height]];
    detail.font = [NSFont systemFontOfSize:12];
    detail.textColor = NSColor.secondaryLabelColor;
    NSTextField *provider = [NSTextField labelWithString:[NSString stringWithFormat:@"Provider %03d · %@",
                                                       BN_PROVIDER_INDEX, number % 2 ? @"Regular + compact" : @"Regular only"]];
    provider.font = [NSFont systemFontOfSize:11];
    provider.textColor = NSColor.secondaryLabelColor;
    NSStackView *stack = [NSStackView stackViewWithViews:@[title, detail, provider]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 8;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:12],
        [stack.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:12],
        [stack.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-12],
        [stack.bottomAnchor constraintLessThanOrEqualToAnchor:self.view.bottomAnchor constant:-12]
    ]];
    BNLog(@"controller.create", _record);
    return self;
}
- (void)dealloc { BNLog(@"controller.deinit", _record); }
@end

@interface BNSettingsController : NSViewController
@property(nonatomic, weak) BNState *state;
- (instancetype)initWithState:(BNState *)state;
@end

@implementation BNSettingsController
- (instancetype)initWithState:(BNState *)state {
    if (!(self = [super initWithNibName:nil bundle:nil])) return nil;
    _state = state;
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 420, 120)];
    NSTextField *title = [NSTextField labelWithString:[NSString stringWithFormat:@"Tab Stress %03d", BN_PROVIDER_INDEX]];
    title.font = [NSFont boldSystemFontOfSize:16];
    NSButton *withdraw = [NSButton buttonWithTitle:@"Withdraw eight tabs" target:self action:@selector(withdraw:)];
    NSButton *restore = [NSButton buttonWithTitle:@"Restore eight tabs" target:self action:@selector(restore:)];
    NSStackView *buttons = [NSStackView stackViewWithViews:@[withdraw, restore]];
    buttons.spacing = 12;
    NSStackView *stack = [NSStackView stackViewWithViews:@[title, buttons]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 16;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [stack.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:16]
    ]];
    self.preferredContentSize = NSMakeSize(420, 120);
    return self;
}
- (void)withdraw:(id)sender { [self.state setTabsVisibleAndPublish:NO]; }
- (void)restore:(id)sender { [self.state setTabsVisibleAndPublish:YES]; }
@end

@implementation BNState
- (instancetype)init {
    if (!(self = [super init])) return nil;
    _active = YES;
    _tabsVisible = YES;
    BNLog(@"instance.create", @{});
    return self;
}
- (const char *)tabsJSON {
    NSMutableArray *tabs = [NSMutableArray array];
    if (self.active && self.tabsVisible) {
        for (NSInteger number = BNFirstTab(); number < BNFirstTab() + 8; number++) {
            NSMutableDictionary *tab = [@{@"id":BNTabID(number), @"title":BNTabTitle(number), @"symbol":@"square.grid.2x2"} mutableCopy];
            // Even tabs deliberately omit the field to exercise the regular-only default.
            if (number % 2) tab[@"presentations"] = @[@"regular", @"compact"];
            [tabs addObject:tab];
        }
    }
    self.snapshot = [[NSJSONSerialization dataWithJSONObject:@{@"tabs":tabs} options:0 error:nil] mutableCopy];
    [self.snapshot appendBytes:"\0" length:1];
    return self.snapshot.bytes;
}
- (void)setTabsVisibleAndPublish:(BOOL)visible {
    if (!self.active || self.tabsVisible == visible) return;
    self.tabsVisible = visible;
    BNLog(visible ? @"tabs.restore" : @"tabs.withdraw", @{});
    if (self.command) self.command(self.context, "tabs.changed", 0);
}
- (void)stop {
    if (!self.active) return;
    self.active = NO;
    self.command = NULL;
    self.context = NULL;
    self.settings.state = nil;
    self.settings = nil;
    BNLog(@"instance.destroy", @{});
}
@end

static NSInteger BNResolveTab(BNState *state, const char *tabID) {
    if (!state.active || !state.tabsVisible || !tabID) return NSNotFound;
    NSString *identifier = [NSString stringWithUTF8String:tabID];
    for (NSInteger number = BNFirstTab(); number < BNFirstTab() + 8; number++) {
        if ([BNTabID(number) isEqualToString:identifier]) return number;
    }
    return NSNotFound;
}

void *bn_extension_create_v1(void *context, BNExtensionCommand command) {
    if (!NSThread.isMainThread) return NULL;
    BNState *state = [BNState new];
    state.context = context;
    state.command = command;
    return (__bridge_retained void *)state;
}
void bn_extension_destroy_v1(void *instance) {
    if (!NSThread.isMainThread || !instance) return;
    BNState *state = (__bridge_transfer BNState *)instance;
    [state stop];
}
void bn_extension_update_v1(void *instance, const uint8_t *json, intptr_t byte_count) {}
void bn_extension_event_v1(void *instance, const char *event) {
    if (!NSThread.isMainThread || !instance || !event) return;
    BNState *state = (__bridge BNState *)instance;
    if (strcmp(event, "stress.tabs.withdraw") == 0) [state setTabsVisibleAndPublish:NO];
    if (strcmp(event, "stress.tabs.restore") == 0) [state setTabsVisibleAndPublish:YES];
}
void *bn_extension_settings_v1(void *instance) {
    if (!NSThread.isMainThread || !instance) return NULL;
    BNState *state = (__bridge BNState *)instance;
    if (!state.active) return NULL;
    if (!state.settings) state.settings = [[BNSettingsController alloc] initWithState:state];
    return (__bridge void *)state.settings;
}
const char *bn_extension_tabs_v1(void *instance) {
    if (!NSThread.isMainThread || !instance) return NULL;
    return [(__bridge BNState *)instance tabsJSON];
}
void *bn_extension_tab_view_v2(void *instance, const char *tab_id, const char *context_json) {
    if (!NSThread.isMainThread || !instance || !context_json) return NULL;
    NSInteger number = BNResolveTab((__bridge BNState *)instance, tab_id);
    if (number == NSNotFound) return NULL;
    size_t length = strnlen(context_json, 65537);
    if (length > 65536) return NULL;
    id context = [NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:context_json length:length] options:0 error:nil];
    if (![context isKindOfClass:NSDictionary.class]) return NULL;
    NSString *presentation = context[@"presentation"];
    id size = context[@"contentSize"];
    if (![presentation isEqual:@"regular"] && ![presentation isEqual:@"compact"]) return NULL;
    if ([presentation isEqual:@"compact"] && number % 2 == 0) return NULL;
    if (![size isKindOfClass:NSDictionary.class] || ![size[@"width"] isKindOfClass:NSNumber.class]
        || ![size[@"height"] isKindOfClass:NSNumber.class]) return NULL;
    double width = [size[@"width"] doubleValue], height = [size[@"height"] doubleValue];
    if (!isfinite(width) || !isfinite(height) || width <= 0 || height <= 0) return NULL;
    return (__bridge_retained void *)[[BNProbeController alloc] initWithTab:number context:context];
}
void *bn_extension_tab_view_v1(void *instance, const char *tab_id, const char *display_id) {
    if (!NSThread.isMainThread || !instance) return NULL;
    NSInteger number = BNResolveTab((__bridge BNState *)instance, tab_id);
    if (number == NSNotFound) return NULL;
    NSDictionary *context = @{@"presentation":@"regular",
                              @"displayID":display_id ? [NSString stringWithUTF8String:display_id] : NSNull.null,
                              @"contentSize":@{@"width":@578, @"height":@132}};
    return (__bridge_retained void *)[[BNProbeController alloc] initWithTab:number context:context];
}
