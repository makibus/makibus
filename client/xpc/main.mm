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
 * The XPC bridge for the sandboxed macOS clients.
 *
 * The bridge exposes the ibus-daemon services as a launchd Mach
 * service so that the sandboxed clients, e.g. the Input Method Kit
 * (IMK) input methods distributed in the App Store, can talk to the
 * ibus-daemon through XPC, which is the only IPC channel allowed for
 * them, while the ibus-daemon and the engines still speak the D-Bus
 * protocol:
 *
 *   sandboxed client --XPC--> ibus-xpc-bridge --D-Bus--> ibus-daemon
 *                                                            |
 *                                                        engines
 *
 * The bridge is launched by launchd on the first connection with the
 * LaunchAgent plist installed from
 * share/ibus/org.freedesktop.IBus.xpc.plist.
 */

#include <ibus.h>

#import <Foundation/Foundation.h>

#include "ibus-xpc.h"

static IBusBus *_bus = NULL;

/* One XPC connection corresponds to one ibus input context. */
@interface IBusXpcSession : NSObject <IBusXpcInputContext>
@property (nonatomic, strong) NSXPCConnection *connection;
@property (nonatomic, assign) IBusInputContext *context;  /* GLib object */
- (id<IBusXpcEngineOutput>)output;
- (void)close;
@end

/* Keep the sessions alive while their XPC connections are up. */
static NSMutableSet<IBusXpcSession *> *_sessions = nil;

/* The requests which arrived before the ibus-daemon connection was
 * established.  They run when the connection is ready or their
 * timeouts fire. */
@interface IBusXpcPending : NSObject
@property (nonatomic, copy) void (^block) (void);
@property (nonatomic, copy) void (^timeout) (void);
@property (nonatomic, assign) BOOL done;
@end

@implementation IBusXpcPending
@end

static NSMutableArray<IBusXpcPending *> *_pending_on_connect = nil;

static void
_finish_pending (IBusXpcPending *pending,
                 void (^runner) (void))
{
    @synchronized (pending) {
        if (pending.done)
            return;
        pending.done = YES;
    }
    runner ();
}

static void
_when_bus_connected (void (^block) (void),
                     void (^timeout) (void))
{
    if (_bus != NULL && ibus_bus_is_connected (_bus)) {
        block ();
        return;
    }
    IBusXpcPending *pending = [[IBusXpcPending alloc] init];
    pending.block = block;
    pending.timeout = timeout;
    @synchronized (_pending_on_connect) {
        [_pending_on_connect addObject:pending];
    }
    dispatch_after (
            dispatch_time (DISPATCH_TIME_NOW,
                           (int64_t) (10 * NSEC_PER_SEC)),
            dispatch_get_global_queue (
                    DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
            ^{
                _finish_pending (pending, ^{ pending.timeout (); });
            });
}

static void
_flush_pending_on_connect (void)
{
    NSArray<IBusXpcPending *> *pending;
    @synchronized (_pending_on_connect) {
        pending = [_pending_on_connect copy];
        [_pending_on_connect removeAllObjects];
    }
    for (IBusXpcPending *p in pending)
        _finish_pending (p, ^{ p.block (); });
}

@implementation IBusXpcSession

- (id<IBusXpcEngineOutput>)output
{
    return (id<IBusXpcEngineOutput>) _connection.remoteObjectProxy;
}

- (void)close
{
    @synchronized (self) {
        if (_context != NULL) {
            g_signal_handlers_disconnect_by_data (_context, (__bridge void *) self);
            g_object_unref (_context);
            _context = NULL;
        }
        _connection = nil;
    }
    @synchronized (_sessions) {
        [_sessions removeObject:self];
    }
}

- (void)createInputContextWithName:(NSString *)name
                             reply:(void (^)(BOOL,
                                             NSString * _Nullable))reply
{
    if (_context != NULL) {
        reply (YES, nil);
        return;
    }
    /* The bridge can be launched by launchd together with the first
     * XPC connection, before the D-Bus connection to the
     * ibus-daemon is established. */
    IBusXpcSession * __unsafe_unretained session = self;
    _when_bus_connected (^{
        [session _createInputContextNowWithName:name reply:reply];
    }, ^{
        reply (NO, @"ibus-daemon connection timeout");
    });
}

- (void)_createInputContextNowWithName:(NSString *)name
                                 reply:(void (^)(BOOL,
                                                 NSString * _Nullable))reply
{
    IBusInputContext *context =
            ibus_bus_create_input_context (_bus, name.UTF8String);
    if (context == NULL) {
        reply (NO, @"Failed to create the input context");
        return;
    }
    g_object_ref_sink (context);

    IBusXpcSession * __unsafe_unretained session = self;
#define CONNECT(signal, callback) \
    g_signal_connect (context, signal, G_CALLBACK (callback), \
                      (__bridge void *) session)

    CONNECT ("commit-text", _context_commit_text_cb);
    CONNECT ("update-preedit-text", _context_update_preedit_text_cb);
    CONNECT ("forward-key-event", _context_forward_key_event_cb);
    CONNECT ("update-auxiliary-text", _context_update_auxiliary_text_cb);
    CONNECT ("update-lookup-table", _context_update_lookup_table_cb);
    CONNECT ("enabled", _context_enabled_cb);
    CONNECT ("disabled", _context_disabled_cb);

    ibus_input_context_set_capabilities (
            context,
            IBUS_CAP_FOCUS | IBUS_CAP_PREEDIT_TEXT |
            IBUS_CAP_AUXILIARY_TEXT | IBUS_CAP_LOOKUP_TABLE);

    _context = context;
    reply (YES, nil);
}

- (void)focusIn
{
    if (_context != NULL)
        ibus_input_context_focus_in (_context);
}

- (void)focusOut
{
    if (_context != NULL)
        ibus_input_context_focus_out (_context);
}

- (void)setCursorLocationX:(NSInteger)x
                         y:(NSInteger)y
                     width:(NSInteger)w
                    height:(NSInteger)h
{
    if (_context != NULL)
        ibus_input_context_set_cursor_location (_context,
                                                 (gint) x, (gint) y,
                                                 (gint) w, (gint) h);
}

/* The reply block of processKeyEventKeyval:...reply: is retained in a
 * C struct because the GDBus async callback data is a plain pointer
 * and a local ARC variable would release the block before the engine
 * replies. */
typedef struct {
    void (^reply) (BOOL);
} IBusXpcKeyReply;

static void
_process_key_event_done (GObject      *source_object,
                         GAsyncResult *res,
                         gpointer      user_data)
{
    IBusXpcKeyReply *data = (IBusXpcKeyReply *) user_data;
    gboolean handled =
            ibus_input_context_process_key_event_async_finish (
                    IBUS_INPUT_CONTEXT (source_object), res, NULL);
    data->reply (handled != FALSE);
    Block_release ((__bridge void *) data->reply);
    g_slice_free (IBusXpcKeyReply, data);
}

- (void)processKeyEventKeyval:(NSUInteger)keyval
                      keycode:(NSUInteger)keycode
                        state:(NSUInteger)state
                         reply:(void (^)(BOOL))reply
{
    if (_context == NULL) {
        reply (NO);
        return;
    }
    IBusXpcKeyReply *data = g_slice_new (IBusXpcKeyReply);
    data->reply = (__bridge void (^)(BOOL)) Block_copy (
            (__bridge void *) reply);
    ibus_input_context_process_key_event_async (
            _context,
            (guint) keyval, (guint) keycode, (guint) state,
            -1, NULL,
            _process_key_event_done,
            data);
}

- (void)reset
{
    if (_context != NULL)
        ibus_input_context_reset (_context);
}

- (void)listEnginesWithReply:(void (^)(NSArray<NSDictionary<
        NSString *, NSString *> *> *))reply
{
    _when_bus_connected (^{
        GList *engines = ibus_bus_list_engines (_bus);
        NSMutableArray *result = [NSMutableArray array];
        for (GList *p = engines; p != NULL; p = p->next) {
            IBusEngineDesc *desc = (IBusEngineDesc *) p->data;
            [result addObject:@{
                @"name": [NSString stringWithUTF8String:
                            ibus_engine_desc_get_name (desc) ?: ""],
                @"longname": [NSString stringWithUTF8String:
                            ibus_engine_desc_get_longname (desc) ?: ""],
                @"description": [NSString stringWithUTF8String:
                            ibus_engine_desc_get_description (desc) ?: ""],
                @"language": [NSString stringWithUTF8String:
                            ibus_engine_desc_get_language (desc) ?: ""],
            }];
        }
        g_list_free_full (engines, g_object_unref);
        reply (result);
    }, ^{
        reply (nil);
    });
}

- (void)setGlobalEngine:(NSString *)engine_name
                   reply:(void (^)(BOOL, NSString * _Nullable))reply
{
    _when_bus_connected (^{
        if (ibus_bus_set_global_engine (_bus, engine_name.UTF8String))
            reply (YES, nil);
        else
            reply (NO, [NSString stringWithFormat:
                    @"Failed to set the engine %@", engine_name]);
    }, ^{
        reply (NO, @"ibus-daemon connection timeout");
    });
}

/* GLib signal callbacks: forward the engine outputs to the client
 * through the XPC connection. */

static void
_context_commit_text_cb (IBusInputContext *context,
                         IBusText         *text,
                         gpointer          user_data)
{
    IBusXpcSession *session =
            (__bridge IBusXpcSession *) user_data;
    [[session output] commitText:
            [NSString stringWithUTF8String:text->text]];
}

static void
_context_update_preedit_text_cb (IBusInputContext *context,
                                 IBusText         *text,
                                 guint             cursor_pos,
                                 gboolean          visible,
                                 gpointer          user_data)
{
    IBusXpcSession *session =
            (__bridge IBusXpcSession *) user_data;
    [[session output] updatePreeditText:
            [NSString stringWithUTF8String:text->text]
            cursor:cursor_pos
            visible:(visible != FALSE)];
}

static void
_context_forward_key_event_cb (IBusInputContext *context,
                               guint             keyval,
                               guint             keycode,
                               guint             state,
                               gpointer          user_data)
{
    IBusXpcSession *session =
            (__bridge IBusXpcSession *) user_data;
    [[session output] forwardKeyEventWithKeyval:keyval
                                        keycode:keycode
                                          state:state];
}

static void
_context_update_auxiliary_text_cb (IBusInputContext *context,
                                   IBusText         *text,
                                   gboolean          visible,
                                   gpointer          user_data)
{
    IBusXpcSession *session =
            (__bridge IBusXpcSession *) user_data;
    if ([[session output] respondsToSelector:
                @selector (updateAuxiliaryText:visible:)]) {
        [[session output] updateAuxiliaryText:
                [NSString stringWithUTF8String:text->text]
                visible:(visible != FALSE)];
    }
}

static void
_context_update_lookup_table_cb (IBusInputContext *context,
                                 IBusLookupTable  *table,
                                 gboolean          visible,
                                 gpointer          user_data)
{
    IBusXpcSession *session =
            (__bridge IBusXpcSession *) user_data;
    if (![[session output] respondsToSelector:
                @selector (updateLookupTable:cursorIndex:visible:)])
        return;

    guint n = ibus_lookup_table_get_number_of_candidates (table);
    guint page_size = ibus_lookup_table_get_page_size (table);
    guint cursor = ibus_lookup_table_get_cursor_pos (table);
    guint page = (page_size > 0) ? cursor / page_size : 0;
    guint first = page * page_size;
    guint i;

    NSMutableArray *candidates = [NSMutableArray array];
    for (i = first; i < n && i < first + page_size; i++) {
        IBusText *text = ibus_lookup_table_get_candidate (table, i);
        [candidates addObject:
                [NSString stringWithUTF8String:text->text]];
    }
    [[session output] updateLookupTable:candidates
                           cursorIndex:cursor
                                visible:(visible != FALSE)];
}

static void
_context_enabled_cb (IBusInputContext *context,
                     gpointer          user_data)
{
    IBusXpcSession *session =
            (__bridge IBusXpcSession *) user_data;
    if ([[session output] respondsToSelector:
                @selector (inputContextEnabled)])
        [[session output] inputContextEnabled];
}

static void
_context_disabled_cb (IBusInputContext *context,
                      gpointer          user_data)
{
    IBusXpcSession *session =
            (__bridge IBusXpcSession *) user_data;
    if ([[session output] respondsToSelector:
                @selector (inputContextDisabled)])
        [[session output] inputContextDisabled];
}

@end

@interface IBusXpcDelegate : NSObject <NSXPCListenerDelegate>
@end

@implementation IBusXpcDelegate

- (BOOL)listener:(NSXPCListener *)listener
        shouldAcceptNewConnection:(NSXPCConnection *)newConnection
{
    /* The Mach services of the per-user launchd are reachable from
     * the processes of the same user session only, which is the same
     * security boundary as the ibus unix socket with the EXTERNAL
     * authentication. */
    IBusXpcSession *session = [[IBusXpcSession alloc] init];
    session.connection = newConnection;

    NSXPCInterface *interface =
            [NSXPCInterface
                    interfaceWithProtocol:@protocol
                            (IBusXpcInputContext)];
    newConnection.exportedInterface = interface;
    newConnection.exportedObject = session;
    newConnection.remoteObjectInterface =
            [NSXPCInterface
                    interfaceWithProtocol:@protocol
                            (IBusXpcEngineOutput)];

    __weak IBusXpcSession *weak_session = session;
    newConnection.invalidationHandler = ^{
        IBusXpcSession *strong_session = weak_session;
        /* The session closes itself when its XPC connection dies. */
        if (strong_session != nil)
            [strong_session close];
    };

    @synchronized (_sessions) {
        [_sessions addObject:session];
    }
    [newConnection resume];
    return YES;
}

@end

/* Run the GLib main loop in the AppKit-less Foundation main run loop
 * with a timer so that the D-Bus signal callbacks are invoked on the
 * main thread. */
static void
_glib_iteration (CFRunLoopTimerRef timer,
                 void             *info)
{
    while (g_main_context_pending (NULL))
        g_main_context_iteration (NULL, FALSE);
}

static void
_bus_connected_cb (IBusBus *bus,
                   gpointer user_data)
{
    g_print ("ibus-xpc-bridge: connected to ibus-daemon\n");
    _flush_pending_on_connect ();
}

static void _bus_disconnected_cb (IBusBus *bus, gpointer user_data);

static gboolean
_reconnect_cb (gpointer user_data)
{
    if (_bus != NULL && ibus_bus_is_connected (_bus))
        return G_SOURCE_REMOVE;
    if (_bus != NULL) {
        g_object_unref (_bus);
        _bus = NULL;
    }
    g_print ("ibus-xpc-bridge: reconnecting to ibus-daemon\n");
    _bus = ibus_bus_new_async_client ();
    g_signal_connect (_bus, "connected",
                      G_CALLBACK (_bus_connected_cb), NULL);
    g_signal_connect (_bus, "disconnected",
                      G_CALLBACK (_bus_disconnected_cb), NULL);
    g_signal_connect (_bus, "disconnected",
                      G_CALLBACK (_bus_disconnected_cb), NULL);
    return G_SOURCE_CONTINUE;
}

static void
_bus_disconnected_cb (IBusBus *bus,
                      gpointer user_data)
{
    g_print ("ibus-xpc-bridge: disconnected from ibus-daemon\n");
    /* The ibus-daemon may be restarted; keep reconnecting so that
     * the bridge recovers without being relaunched. */
    g_timeout_add_seconds (1, _reconnect_cb, NULL);
}

int
main (int    argc,
      char **argv)
{
    @autoreleasepool {
        ibus_init ();

        _bus = ibus_bus_new_async_client ();
        g_signal_connect (_bus, "connected",
                          G_CALLBACK (_bus_connected_cb), NULL);

        _sessions = [NSMutableSet set];
        _pending_on_connect = [NSMutableArray array];

        IBusXpcDelegate *delegate = [[IBusXpcDelegate alloc] init];
        NSXPCListener *listener =
                [[NSXPCListener alloc]
                        initWithMachServiceName:@IBUS_XPC_SERVICE_NAME];

        /* Optionally restrict the clients to the signed binaries,
         * e.g. with:
         *   anchor apple generic and identifier "com.example.Ime" ...
         * The requirement string follows
         * https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/RequirementLang/RequirementLang.html
         */
        if (@available (macOS 13, *)) {
            NSString *requirement =
                    [[NSProcessInfo processInfo] environment]
                            [@"IBUS_XPC_CODE_SIGNING_REQUIREMENT"];
            if (requirement.length > 0) {
                [listener setConnectionCodeSigningRequirement:requirement];
                g_print ("ibus-xpc-bridge: restricted the connections to "
                         "the code signing requirement\n");
            }
        }

        listener.delegate = delegate;
        [listener resume];

        CFRunLoopTimerContext context = { 0, NULL, NULL, NULL, NULL };
        CFRunLoopTimerRef timer = CFRunLoopTimerCreate (
                kCFAllocatorDefault, 0, 0.01, 0, 0,
                _glib_iteration, &context);
        CFRunLoopAddTimer (CFRunLoopGetMain (), timer,
                           kCFRunLoopCommonModes);

        [[NSRunLoop mainRunLoop] run];

        CFRunLoopRemoveTimer (CFRunLoopGetMain (), timer,
                              kCFRunLoopCommonModes);
        CFRelease (timer);
    }
    return EXIT_SUCCESS;
}
