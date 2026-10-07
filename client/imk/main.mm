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

#import <Carbon/Carbon.h>
#import <CoreGraphics/CoreGraphics.h>
#include <string.h>

#import "IBusKeyConvert.h"

static NSEvent *
_fake_key (unichar ch, NSUInteger flags, unsigned short keycode)
{
    NSString *characters = [NSString stringWithCharacters:&ch length:1];
    NSString *plain = [characters lowercaseString];
    return [NSEvent keyEventWithType:NSEventTypeKeyDown
                            location:NSZeroPoint
                       modifierFlags:flags
                           timestamp:0
                        windowNumber:0
                             context:nil
                          characters:(flags & NSShiftKeyMask) ?
                                      characters : plain
         charactersIgnoringModifiers:plain
                       isARepeat:NO
                         keyCode:keycode];
}

static int
_run_conversion_tests (void)
{
    int failures = 0;
#define EXPECT(desc, cond) do { \
    if (!(cond)) { printf ("FAIL: %s\n", desc); failures++; } \
} while (0)

    EXPECT ("keyval 'a'", ibus_keyval_from_event (
            _fake_key ('a', 0, kVK_ANSI_A)) == IBUS_KEY_a);
    EXPECT ("keyval 'A' with Shift",
            ibus_keyval_from_event (
                    _fake_key ('A', NSEventModifierFlagShift,
                               kVK_ANSI_A)) == IBUS_KEY_A);
    EXPECT ("keyval Return",
            ibus_keyval_from_event (
                    _fake_key ('\r', 0, kVK_Return)) == IBUS_KEY_Return);
    EXPECT ("keycode 'h' XKB",
            ibus_mac_keycode_to_xkb (kVK_ANSI_H) == 43);
    EXPECT ("state shift+ctrl",
            ibus_state_from_modifier_flags (
                    NSEventModifierFlagShift | NSEventModifierFlagControl,
                    NO) ==
            (IBUS_SHIFT_MASK | IBUS_CONTROL_MASK));
    EXPECT ("state command",
            ibus_state_from_modifier_flags (
                    NSEventModifierFlagCommand, NO) == IBUS_MOD4_MASK);

    /* The flagsChanged NSEvent is built from a CGEvent since the
     * keyCode of an NSEvent cannot be assigned directly. */
    CGEventRef cg = CGEventCreateKeyboardEvent (NULL, kVK_Shift, true);
    CGEventSetFlags (cg, (CGEventFlags) kCGEventFlagMaskShift);
    NSEvent *shiftDown = [NSEvent eventWithCGEvent:cg];
    CFRelease (cg);
    uint32_t keyval = 0, keycode = 0;
    EXPECT ("modifier event Shift_L",
            ibus_modifier_event (shiftDown, &keyval, &keycode) &&
            keyval == IBUS_KEY_Shift_L && keycode == 50);

    printf (failures ? "conversion tests FAILED\n" : "conversion tests OK\n");
    return failures;
}

static int
_run_selftest (void)
{
    int failures = _run_conversion_tests ();
    if (failures)
        return EXIT_FAILURE;
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
        struct { uint32_t keyval; uint32_t keycode; NSUInteger state; } keys[] = {
            { IBUS_KEY_U,      30, IBUS_SHIFT_MASK | IBUS_CONTROL_MASK },
            { '4',             13, IBUS_SHIFT_MASK | IBUS_CONTROL_MASK },
            { '1',             10, IBUS_SHIFT_MASK | IBUS_CONTROL_MASK },
            { IBUS_KEY_space,  65, IBUS_SHIFT_MASK | IBUS_CONTROL_MASK },
        };
        for (size_t i = 0; i < sizeof (keys) / sizeof (keys[0]); i++) {
            const uint32_t keyval = keys[i].keyval;
            const uint32_t keycode = keys[i].keycode;
            const NSUInteger state = keys[i].state;
            dispatch_semaphore_t done = dispatch_semaphore_create (0);
            [client processKeyEventKeyval:keyval
                                  keycode:keycode
                                    state:state
                                     reply:^(BOOL handled) {
                printf ("key %u handled: %d\n", (unsigned) keyval, handled);
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

/* Send the plain ASCII keys to the given engine and print the
 * engine outputs; used with the real engines, e.g.:
 *   ibus-im --keys rime nihao
 */
static int
_run_keys (const char *engine_name, const char *keys)
{
    printf ("ibus-im: engine \"%s\", keys \"%s\"\n",
            engine_name, keys);
    IBusXpcClient *client = [IBusXpcClient sharedClient];

    __block BOOL got_output = NO;
    dispatch_semaphore_t output_seen = dispatch_semaphore_create (0);
    IBusSelftestOutput *output = [[IBusSelftestOutput alloc] init];
    output.commitHandler = ^(NSString *text) {
        printf (">>> COMMIT: \"%s\"\n", text.UTF8String);
        got_output = YES;
        dispatch_semaphore_signal (output_seen);
    };
    output.preeditHandler = ^(NSString *text) {
        printf (">>> PREEDIT: \"%s\"\n", text.UTF8String);
        got_output = YES;
    };
    client.delegate = output;

    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
    while (![client contextReady] && [deadline timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop]
                runMode:NSDefaultRunLoopMode
             beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    }
    if (![client contextReady]) {
        printf ("cannot create the input context\n");
        return EXIT_FAILURE;
    }

    [client focusIn];
    [[client context] setGlobalEngine:@(engine_name)
                                 reply:^(BOOL ok, NSString *error) {
        if (!ok)
            printf ("setGlobalEngine failed: %s\n", error.UTF8String);
        dispatch_semaphore_signal (output_seen);
    }];
    /* Wait for the asynchronous engine spawn and binding on the
     * daemon side before the first key, then re-focus so that the
     * panel proxy, which may have connected after the first focus,
     * tracks this input context for the lookup table forwarding. */
    sleep (2);

    dispatch_async (
            dispatch_get_global_queue (DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
            ^{
        for (const char *p = keys; *p != '\0'; p++) {
            const uint32_t keyval = (uint32_t) *p;
            const uint32_t keycode = ibus_keycode_for_ascii (*p);
            dispatch_semaphore_t done = dispatch_semaphore_create (0);
            [client processKeyEventKeyval:keyval
                                  keycode:keycode
                                    state:0
                                     reply:^(BOOL handled) {
                printf ("key '%c' handled: %d\n", *p, handled);
                dispatch_semaphore_signal (done);
            }];
            dispatch_semaphore_wait (done,
                    dispatch_time (DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
            [client processKeyEventKeyval:keyval
                                  keycode:keycode
                                    state:IBUS_RELEASE_MASK
                                   reply:^(BOOL handled) {}];
            usleep (100000);
        }
        /* Give the engine a moment for the outputs. */
        sleep (1);
        dispatch_semaphore_signal (output_seen);
    });

    NSDate *finish = [NSDate dateWithTimeIntervalSinceNow:15];
    while ([finish timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop]
                runMode:NSDefaultRunLoopMode
             beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
        /* Commit any pending preedit with the Return key? Not for
         * rime: the preedit stays until a selection. */
        if (got_output)
            continue;
    }
    printf (got_output ? "engine produced output\n"
                       : "no engine output\n");
    return got_output ? EXIT_SUCCESS : EXIT_FAILURE;
}

int
main (int    argc,
      char **argv)
{
    @autoreleasepool {
        if (argc > 1 && strcmp (argv[1], "--selftest") == 0)
            return _run_selftest ();
        if (argc > 1 && strcmp (argv[1], "--keys") == 0) {
            const char *engine = argc > 2 ? argv[2] : "xkb:us::eng";
            const char *keys = argc > 3 ? argv[3] : "";
            return _run_keys (engine, keys);
        }

        /* The connection name must match the
         * InputMethodConnectionName of the Info.plist, which the
         * system input method host uses to connect. */
        IMKServer *server = [[IMKServer alloc]
                initWithName:@"org.freedesktop.IBus.IM.Connection"
                bundleIdentifier:[[NSBundle mainBundle] bundleIdentifier]];

        [[NSApplication sharedApplication] run];
        (void) server;
    }
    return EXIT_SUCCESS;
}
