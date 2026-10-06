/* -*- mode: C; c-basic-offset: 4; indent-tabs-mode: nil; -*- */
/* vim:set et sts=4: */
/* ibus - The Input Bus
 * Copyright (C) 2026 Weixuan XIAO <veyx.shaw@gmail.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public License
 * as published by the Free Software Foundation; either version 2.1 of
 * the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
 * 02110-1301 USA
 */

/*
 * The Input Method Kit (IMK) front end of the ibus input method.
 *
 * The input method receives the key events with handleEvent:client:
 * of IBusInputController, forwards them to the ibus-daemon through
 * the XPC bridge and applies the engine outputs with the IMK text
 * input APIs, i.e. setMarkedText for the pre-edit text and insertText
 * for the committed text.
 *
 * Run with --selftest to verify the XPC round trip of this executable
 * without enabling the input method in System Settings.
 */

#import <AppKit/AppKit.h>
#import <InputMethodKit/InputMethodKit.h>
#import <ibus.h>

#import "IBusInputController.h"
#import "ibus-xpc.h"

/* A plain delegate for the selftest mode which prints the engine
 * outputs instead of applying them to a text input client. */
@interface IBusSelftestOutput : NSObject <IBusXpcClientDelegate>
@property (nonatomic, copy) void (^commitHandler) (NSString *);
@property (nonatomic, copy) void (^preeditHandler) (NSString *);
@end

@implementation IBusSelftestOutput
- (void)xpcClient:(IBusXpcClient *)client commitText:(NSString *)text
{
    if (self.commitHandler)
        self.commitHandler (text);
}
- (void)xpcClient:(IBusXpcClient *)client
        updatePreedit:(NSString *)text
              cursor:(NSUInteger)cursor
            visible:(BOOL)visible
{
    if (self.preeditHandler)
        self.preeditHandler (text);
}
@end

static int
_run_selftest (void)
{
    printf ("ibus-im selftest: connecting to the XPC bridge...\n");
    IBusXpcClient *client = [IBusXpcClient sharedClient];

    __block BOOL got_commit = NO;
    dispatch_semaphore_t committed = dispatch_semaphore_create (0);
    IBusSelftestOutput *output = [[IBusSelftestOutput alloc] init];
    output.commitHandler = ^(NSString *text) {
        printf (">>> COMMIT: \"%s\"\n", text.UTF8String);
        got_commit = YES;
        dispatch_semaphore_signal (committed);
    };
    output.preeditHandler = ^(NSString *text) {
        printf (">>> PREEDIT: \"%s\"\n", text.UTF8String);
    };
    client.delegate = output;

    /* The bridge may be launched by this connection and the input
     * context is created asynchronously; wait for it. */
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
    while (![client contextReady] &&
           [deadline timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop]
                runMode:NSDefaultRunLoopMode
             beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    }
    if (![client contextReady]) {
        printf ("ibus-im selftest: cannot create the input context\n");
        return EXIT_FAILURE;
    }

    [client focusIn];
    [[client context] setGlobalEngine:@"xkb:us::eng"
                                reply:^(BOOL ok, NSString *error) {
        if (!ok)
            printf ("setGlobalEngine failed: %s\n", error.UTF8String);
    }];

    /* Ctrl+Shift+U, "4", "1", Space commits U+0041 'A'.  The keys
     * are sent on a background queue because the replies block the
     * sending thread, while the engine outputs are marshalled to the
     * main run loop by the IBusXpcClient delegate. */
    dispatch_async (
            dispatch_get_global_queue (DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
            ^{
        struct { guint keyval; guint keycode; NSUInteger state; } keys[] = {
            { IBUS_KEY_U,      30, IBUS_SHIFT_MASK | IBUS_CONTROL_MASK },
            { IBUS_KEY_4,      13, IBUS_SHIFT_MASK | IBUS_CONTROL_MASK },
            { IBUS_KEY_1,      10, IBUS_SHIFT_MASK | IBUS_CONTROL_MASK },
            { IBUS_KEY_space,  65, IBUS_SHIFT_MASK | IBUS_CONTROL_MASK },
        };
        for (size_t i = 0; i < G_N_ELEMENTS (keys); i++) {
            const guint keyval = keys[i].keyval;
            const guint keycode = keys[i].keycode;
            const NSUInteger state = keys[i].state;
            dispatch_semaphore_t done = dispatch_semaphore_create (0);
            [client processKeyEventKeyval:keyval
                                  keycode:keycode
                                    state:state
                                     reply:^(BOOL handled) {
                printf ("key %u handled: %d\n", keyval, handled);
                dispatch_semaphore_signal (done);
            }];
            dispatch_semaphore_wait (done,
                    dispatch_time (DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
            [client processKeyEventKeyval:keyval
                                  keycode:keycode
                                    state:state | IBUS_RELEASE_MASK
                                     reply:^(BOOL handled) {}];
        }
    });

    NSDate *commit_deadline = [NSDate dateWithTimeIntervalSinceNow:10];
    while (!got_commit && [commit_deadline timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop]
                runMode:NSDefaultRunLoopMode
             beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    }
    printf (got_commit ?
            "ibus-im selftest OK\n" : "ibus-im selftest FAILED\n");
    return got_commit ? EXIT_SUCCESS : EXIT_FAILURE;
}

int
main (int    argc,
      char **argv)
{
    @autoreleasepool {
        if (argc > 1 && g_strcmp0 (argv[1], "--selftest") == 0)
            return _run_selftest ();

        /* The IMK server name is the mach service name which the
         * system input method host connects to. */
        IMKServer *server = [[IMKServer alloc]
                initWithName:@"org.freedesktop.IBus.IM"
                bundleIdentifier:[[NSBundle mainBundle] bundleIdentifier]];

        [[NSApplication sharedApplication] run];
        (void) server;
    }
    return EXIT_SUCCESS;
}
