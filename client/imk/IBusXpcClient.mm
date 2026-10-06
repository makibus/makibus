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

#import "IBusXpcClient.h"

/* The engine outputs arrive on the main thread because the remote
 * object proxy of the NSXPCConnection is called from the GCD queue of
 * the connection; marshal them to the main queue where the IMK
 * controllers live. */
@implementation IBusXpcClient {
    NSXPCConnection *_connection;
    id<IBusXpcInputContext> _context;
    BOOL _creating;
    BOOL _ready;
}

+ (instancetype)sharedClient
{
    static IBusXpcClient *client = nil;
    static dispatch_once_t once;
    dispatch_once (&once, ^{
        client = [[IBusXpcClient alloc] init];
    });
    return client;
}

- (id)init
{
    self = [super init];
    if (self) {
        [self _connect];
    }
    return self;
}

- (void)_connect
{
    if (_connection != nil)
        return;
    _connection = [[NSXPCConnection alloc]
            initWithMachServiceName:@IBUS_XPC_SERVICE_NAME
                            options:0];
    _connection.exportedInterface =
            [NSXPCInterface
                    interfaceWithProtocol:@protocol
                            (IBusXpcEngineOutput)];
    _connection.exportedObject = self;
    _connection.remoteObjectInterface =
            [NSXPCInterface
                    interfaceWithProtocol:@protocol
                            (IBusXpcInputContext)];
    __weak IBusXpcClient *weak_self = self;
    _connection.invalidationHandler = ^{
        dispatch_async (dispatch_get_main_queue (), ^{
            IBusXpcClient *strong_self = weak_self;
            if (strong_self == nil)
                return;
            /* The bridge is launched by launchd on demand and may be
             * down; reconnect on the next event. */
            strong_self->_connection = nil;
            strong_self->_context = nil;
            strong_self->_creating = NO;
        });
    };
    [_connection resume];
}

- (BOOL)contextReady
{
    /* Trigger the input context creation on the first check. */
    if (!_ready)
        [self context];
    return _ready;
}

- (id<IBusXpcInputContext>)context
{
    if (_connection == nil)
        [self _connect];
    if (_connection == nil)
        return nil;
    if (_context == nil && !_creating) {
        _creating = YES;
        __weak IBusXpcClient *weak_self = self;
        [[(NSXPCConnection *) _connection
                remoteObjectProxyWithErrorHandler:^(NSError *error) {
            IBusXpcClient *strong_self = weak_self;
            if (strong_self != nil)
                strong_self->_creating = NO;
        }] createInputContextWithName:@"macos-imk"
                                reply:^(BOOL ok, NSString *error) {
            IBusXpcClient *strong_self = weak_self;
            if (strong_self == nil)
                return;
            /* Set the plain flags on the connection queue directly;
             * the delegate outputs are marshalled to the main queue
             * separately. */
            strong_self->_creating = NO;
            strong_self->_ready = ok;
            if (!ok)
                NSLog (@"ibus: cannot create the input context: %@",
                       error);
        }];
        /* Return the proxy directly; the early events are delivered
         * to the bridge and the pending create is buffered there. */
        _context = (id<IBusXpcInputContext>)
                [(NSXPCConnection *) _connection remoteObjectProxy];
    }
    return _context;
}

- (BOOL)processKeyEventKeyval:(NSUInteger)keyval
                      keycode:(NSUInteger)keycode
                        state:(NSUInteger)state
                        reply:(void (^)(BOOL))reply
{
    id<IBusXpcInputContext> context = [self context];
    if (context == nil)
        return NO;
    /* The reply is called on the connection GCD queue directly since
     * the sender, e.g. handleEvent:client:, may block the main
     * thread waiting for it. */
    [context processKeyEventKeyval:keyval
                           keycode:keycode
                             state:state
                              reply:reply];
    return YES;
}

- (void)focusIn
{
    [[self context] focusIn];
}

- (void)focusOut
{
    [[self context] focusOut];
}

- (void)reset
{
    [[self context] reset];
}

- (void)setCursorLocationX:(NSInteger)x y:(NSInteger)y
                    width:(NSInteger)w height:(NSInteger)h
{
    [[self context] setCursorLocationX:x y:y width:w height:h];
}

/* IBusXpcEngineOutput; called on the connection GCD queue. */

- (void)_onMain:(void (^)(id<IBusXpcClientDelegate>))block
{
    dispatch_async (dispatch_get_main_queue (), ^{
        block (self.delegate);
    });
}

- (void)commitText:(NSString *)text
{
    [self _onMain:^(id<IBusXpcClientDelegate> delegate) {
        [delegate xpcClient:self commitText:text];
    }];
}

- (void)updatePreeditText:(NSString *)text
                   cursor:(NSUInteger)cursor
                   visible:(BOOL)visible
{
    [self _onMain:^(id<IBusXpcClientDelegate> delegate) {
        [delegate xpcClient:self updatePreedit:text
                                    cursor:cursor
                                  visible:visible];
    }];
}

/* The optional engine outputs are not forwarded to the delegate in
 * this front end: the candidates and the auxiliary texts are
 * rendered by the native ibus panel (ibus-ui-macospanel) and the
 * pre-edit text is applied with setMarkedText.  The methods are
 * implemented anyway because the NSXPCConnection proxy answers
 * respondsToSelector: for all the methods enabled in the interface
 * and an unimplemented method would abort the process. */

- (void)showPreedit
{
}

- (void)hidePreedit
{
}

- (void)updateAuxiliaryText:(NSString *)text visible:(BOOL)visible
{
}

- (void)updateLookupTable:(NSArray<NSString *> *)candidates
              cursorIndex:(NSUInteger)cursorIndex
                   visible:(BOOL)visible
{
}

- (void)inputContextEnabled
{
}

- (void)inputContextDisabled
{
}

- (void)forwardKeyEventWithKeyval:(NSUInteger)keyval
                          keycode:(NSUInteger)keycode
                            state:(NSUInteger)state
{
    [self _onMain:^(id<IBusXpcClientDelegate> delegate) {
        if (delegate != nil &&
            [delegate respondsToSelector:
                    @selector (xpcClientForwardKey:keyval:keycode:state:)])
            [delegate xpcClientForwardKey:self
                                   keyval:keyval
                                  keycode:keycode
                                    state:state];
    }];
}

@end
