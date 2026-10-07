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
 * A test client of the ibus XPC bridge.  It sends the hex compose
 * sequence (Ctrl+Shift+U, "41", Space) through the bridge, which
 * commits "A" (U+0041) from the engine if the daemon is started with
 * IBUS_ENABLE_CTRL_SHIFT_U=1.
 */

#import <ibus.h>

#include "ibus-xpc.h"
#include "ibus-mac-keycode.h"

@interface IBusXpcTestOutput : NSObject <IBusXpcEngineOutput>
@property (nonatomic, assign) BOOL gotCommit;
@end

@implementation IBusXpcTestOutput

- (void)commitText:(NSString *)text
{
    self.gotCommit = YES;
    printf (">>> COMMIT: \"%s\"\n", text.UTF8String);
}

- (void)updatePreeditText:(NSString *)text
                   cursor:(NSUInteger)cursor
                   visible:(BOOL)visible
{
    printf (">>> PREEDIT: \"%s\" cursor:%lu visible:%d\n",
            text.UTF8String, (unsigned long) cursor, visible);
}

- (void)forwardKeyEventWithKeyval:(NSUInteger)keyval
                          keycode:(NSUInteger)keycode
                            state:(NSUInteger)state
{
    printf (">>> FORWARD: keyval:%lu keycode:%lu state:%lu\n",
            (unsigned long) keyval, (unsigned long) keycode,
            (unsigned long) state);
}

- (void)updateLookupTable:(NSArray<NSString *> *)candidates
              cursorIndex:(NSUInteger)cursorIndex
                   visible:(BOOL)visible
{
    printf (">>> CANDIDATES: [%@] cursor:%lu visible:%d\n",
            [candidates componentsJoinedByString:@", "],
            (unsigned long) cursorIndex, visible);
}

@end

static int
_run_keys (const char *engine_name, const char *keys)
{
    IBusXpcTestOutput *output = [[IBusXpcTestOutput alloc] init];

    NSXPCConnection *connection =
            [[NSXPCConnection alloc]
                    initWithMachServiceName:@IBUS_XPC_SERVICE_NAME
                                    options:0];
    connection.exportedInterface =
            [NSXPCInterface
                    interfaceWithProtocol:@protocol
                            (IBusXpcEngineOutput)];
    connection.exportedObject = output;
    connection.remoteObjectInterface =
            [NSXPCInterface
                    interfaceWithProtocol:@protocol
                            (IBusXpcInputContext)];
    [connection resume];

    id<IBusXpcInputContext> ic =
            (id<IBusXpcInputContext>) [connection
                    remoteObjectProxyWithErrorHandler:^(NSError *error) {
                printf (">>> XPC ERROR: %s\n",
                        error.localizedDescription.UTF8String);
            }];

    dispatch_semaphore_t created = dispatch_semaphore_create (0);
    [ic createInputContextWithName:@"xpc-keys"
                             reply:^(BOOL ok,
                                     NSString *error) {
        if (!ok) {
            printf ("createInputContext failed: %s\n",
                    error.UTF8String);
            exit (EXIT_FAILURE);
        }
        dispatch_semaphore_signal (created);
    }];
    if (dispatch_semaphore_wait (created,
            dispatch_time (DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC))) {
        printf ("timeout to create the input context\n");
        return EXIT_FAILURE;
    }
    [ic setGlobalEngine:@(engine_name)
                  reply:^(BOOL ok, NSString *error) {
        if (!ok)
            printf ("setGlobalEngine failed: %s\n",
                    error.UTF8String);
    }];
    [ic focusIn];
    /* Wait for the asynchronous engine spawn and binding. */
    sleep (2);

    __block BOOL got_output = NO;
    for (const char *p = keys; *p != '\0'; p++) {
        const uint32_t keyval = (uint32_t) *p;
        const uint32_t keycode = ibus_keycode_for_ascii (*p);
        dispatch_semaphore_t replied = dispatch_semaphore_create (0);
        [ic processKeyEventKeyval:keyval
                          keycode:keycode
                            state:0
                             reply:^(BOOL handled) {
            printf ("key '%c' handled: %d\n", *p, handled);
            if (handled)
                got_output = YES;
            dispatch_semaphore_signal (replied);
        }];
        dispatch_semaphore_wait (replied,
                dispatch_time (DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
        [ic processKeyEventKeyval:keyval
                          keycode:keycode
                            state:IBUS_RELEASE_MASK
                           reply:^(BOOL handled) {}];
        usleep (100000);
    }
    /* Let the async outputs arrive. */
    sleep (1);

    printf (got_output ? "XPC keys round trip OK\n"
                       : "no engine output\n");
    [connection invalidate];
    return got_output ? EXIT_SUCCESS : EXIT_FAILURE;
}

int
main (int    argc,
      char **argv)
{
    @autoreleasepool {
        /* --keys <engine> <text> sends the plain ASCII text to the
         * given engine, e.g. --keys rime nihao; the default run is
         * the hex compose sequence which commits "A" with the
         * xkb:us::eng engine. */
        if (argc > 1 && strcmp (argv[1], "--keys") == 0) {
            const char *engine = argc > 2 ? argv[2] : "xkb:us::eng";
            const char *keys = argc > 3 ? argv[3] : "";
            return _run_keys (engine, keys);
        }
        IBusXpcTestOutput *output = [[IBusXpcTestOutput alloc] init];

        NSXPCConnection *connection =
                [[NSXPCConnection alloc]
                        initWithMachServiceName:@IBUS_XPC_SERVICE_NAME
                                        options:0];
        connection.exportedInterface =
                [NSXPCInterface
                        interfaceWithProtocol:@protocol
                                (IBusXpcEngineOutput)];
        connection.exportedObject = output;
        connection.remoteObjectInterface =
                [NSXPCInterface
                        interfaceWithProtocol:@protocol
                                (IBusXpcInputContext)];
        [connection resume];

        connection.invalidationHandler = ^{
            printf (">>> CONNECTION INVALIDATED\n");
        };
        id<IBusXpcInputContext> ic =
                (id<IBusXpcInputContext>) [connection
                        remoteObjectProxyWithErrorHandler:^(NSError *error) {
                    printf (">>> XPC ERROR: %s\n",
                            error.localizedDescription.UTF8String);
                }];

        dispatch_semaphore_t created = dispatch_semaphore_create (0);
        [ic createInputContextWithName:@"xpc-test"
                                 reply:^(BOOL ok,
                                         NSString *error) {
            if (!ok) {
                printf ("createInputContext failed: %s\n",
                        error.UTF8String);
                exit (EXIT_FAILURE);
            }
            dispatch_semaphore_signal (created);
        }];
        if (dispatch_semaphore_wait (created,
                                     dispatch_time (DISPATCH_TIME_NOW,
                                                    5 * NSEC_PER_SEC))) {
            printf ("timeout to create the input context; " \
                    "is the bridge running?\n");
            return EXIT_FAILURE;
        }

        [ic setGlobalEngine:@"xkb:us::eng"
                      reply:^(BOOL ok, NSString *error) {
            if (!ok)
                printf ("setGlobalEngine failed: %s\n",
                        error.UTF8String);
        }];
        [ic focusIn];
        [ic setCursorLocationX:100 y:100 width:10 height:16];

        /* Ctrl+Shift+U, "4", "1", Space commits U+0041 'A'. */
        NSArray<NSNumber *> *keys = @[
            @[@(IBUS_KEY_U), @(30), @((NSUInteger) (4 | 1))],
            @[@(IBUS_KEY_4), @(13), @((NSUInteger) (4 | 1))],
            @[@(IBUS_KEY_1), @(10), @((NSUInteger) (4 | 1))],
            @[@(IBUS_KEY_space), @(65), @((NSUInteger) (4 | 1))],
        ];
        for (NSArray<NSNumber *> *key in keys) {
            dispatch_semaphore_t replied =
                    dispatch_semaphore_create (0);
            printf ("sending key %lu\n",
                    (unsigned long) key[0].unsignedIntegerValue);
            [ic processKeyEventKeyval:key[0].unsignedIntegerValue
                              keycode:key[1].unsignedIntegerValue
                                state:key[2].unsignedIntegerValue
                                 reply:^(BOOL handled) {
                printf ("key %lu handled: %d\n",
                        (unsigned long) key[0].unsignedIntegerValue,
                        handled);
                dispatch_semaphore_signal (replied);
            }];
            if (dispatch_semaphore_wait (replied,
                                         dispatch_time (DISPATCH_TIME_NOW,
                                                        5 * NSEC_PER_SEC)))
                printf ("key %lu reply TIMEOUT\n",
                        (unsigned long) key[0].unsignedIntegerValue);
            /* Send the release event without waiting. */
            [ic processKeyEventKeyval:key[0].unsignedIntegerValue
                              keycode:key[1].unsignedIntegerValue
                                state:key[2].unsignedIntegerValue |
                                        (1u << 30)
                                 reply:^(BOOL handled) {}];
        }

        /* Wait for the commit output. */
        for (int i = 0; i < 50 && !output.gotCommit; i++) {
            [[NSRunLoop currentRunLoop]
                    runMode:NSDefaultRunLoopMode
                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        }

        printf (output.gotCommit ?
                "XPC bridge round trip OK\n" :
                "No commit received\n");
        [connection invalidate];
        return output.gotCommit ? EXIT_SUCCESS : EXIT_FAILURE;
    }
}
