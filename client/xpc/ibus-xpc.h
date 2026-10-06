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

#ifndef __IBUS_XPC_H_
#define __IBUS_XPC_H_

#import <Foundation/Foundation.h>
#import <Foundation/NSXPCConnection.h>

/* The launchd Mach service name of the ibus XPC bridge. */
#define IBUS_XPC_SERVICE_NAME "org.freedesktop.IBus.xpc"

/* The protocol which the bridge exports to the clients.  The keycode
 * follows the XKB convention, i.e. the macOS virtual keycodes
 * (kVK_ANSI_*) plus 8, and the modifiers follow the ibus convention,
 * e.g. IBUS_SHIFT_MASK | IBUS_CONTROL_MASK. */
@protocol IBusXpcInputContext <NSObject>
/* Create an ibus input context for this connection. */
- (void)createInputContextWithName:(NSString *)name
                             reply:(void (^)(BOOL ok,
                                             NSString * _Nullable error))
                                     reply;
- (void)focusIn;
- (void)focusOut;
- (void)setCursorLocationX:(NSInteger)x
                         y:(NSInteger)y
                     width:(NSInteger)w
                    height:(NSInteger)h;
/* Send a key event to the engine.  The reply is called with whether
 * the engine consumed the key event. */
- (void)processKeyEventKeyval:(NSUInteger)keyval
                      keycode:(NSUInteger)keycode
                        state:(NSUInteger)state
                         reply:(void (^)(BOOL handled))reply;
/* Select the global engine, e.g. "xkb:us::eng", since the
 * ibus-daemon runs in the global engine mode by default and the
 * per-context SetEngine is rejected there. */
- (void)setGlobalEngine:(NSString *)engine_name
                   reply:(void (^)(BOOL ok,
                                   NSString * _Nullable error))reply;
/* List the registered engines; each dictionary has the name,
 * longname, description and language keys. */
- (void)listEnginesWithReply:(void (^)(NSArray<NSDictionary<
        NSString *, NSString *> *> * _Nullable engines))reply;
- (void)reset;
@end

/* The protocol which the clients export to receive the engine
 * outputs. */
@protocol IBusXpcEngineOutput <NSObject>
- (void)commitText:(NSString *)text;
- (void)updatePreeditText:(NSString *)text
                   cursor:(NSUInteger)cursor
                   visible:(BOOL)visible;
- (void)forwardKeyEventWithKeyval:(NSUInteger)keyval
                          keycode:(NSUInteger)keycode
                            state:(NSUInteger)state;
@optional
- (void)showPreedit;
- (void)hidePreedit;
- (void)updateAuxiliaryText:(NSString *)text visible:(BOOL)visible;
- (void)updateLookupTable:(NSArray<NSString *> *)candidates
              cursorIndex:(NSUInteger)cursorIndex
                   visible:(BOOL)visible;
- (void)inputContextEnabled;
- (void)inputContextDisabled;
@end

#endif
