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

#ifndef __IBUS_XPC_CLIENT_H_
#define __IBUS_XPC_CLIENT_H_

#import <AppKit/AppKit.h>

#import "ibus-xpc.h"

/* The delegate receives the engine outputs of the shared XPC input
 * context. */
@class IBusXpcClient;

@protocol IBusXpcClientDelegate <NSObject>
- (void)xpcClient:(IBusXpcClient *)client
      commitText:(NSString *)text;
- (void)xpcClient:(IBusXpcClient *)client
   updatePreedit:(NSString *)text
             cursor:(NSUInteger)cursor
           visible:(BOOL)visible;
@optional
- (void)xpcClientForwardKey:(IBusXpcClient *)client
                     keyval:(NSUInteger)keyval
                    keycode:(NSUInteger)keycode
                      state:(NSUInteger)state;
@end

/* The shared connection to the ibus XPC bridge of the input method
 * process.  The connection is re-established on demand. */
@interface IBusXpcClient : NSObject <IBusXpcEngineOutput>

@property (nonatomic, weak) id<IBusXpcClientDelegate> delegate;

+ (instancetype)sharedClient;

- (id<IBusXpcInputContext>)context;

/* true after the input context was created on the bridge; the early
 * key events are buffered by the bridge until then. */
@property (nonatomic, readonly) BOOL contextReady;

/* true if the input event was sent to the engine; false if the
 * connection is down and the sender should handle the event
 * locally. */
- (BOOL)processKeyEventKeyval:(NSUInteger)keyval
                      keycode:(NSUInteger)keycode
                        state:(NSUInteger)state
                        reply:(void (^)(BOOL handled))reply;

- (void)focusIn;
- (void)focusOut;
- (void)reset;
- (void)setCursorLocationX:(NSInteger)x y:(NSInteger)y
                    width:(NSInteger)w height:(NSInteger)h;

/* The cached engine descriptions of the last refreshEngines call,
 * each with the name, longname, description and language keys. */
@property (nonatomic, copy)
        NSArray<NSDictionary<NSString *, NSString *> *> *engines;

/* Refresh the engines cache asynchronously. */
- (void)refreshEngines;

/* The input method menu with the engine list; the target of the menu
 * items is the shared client which outlives the IMK controllers. */
- (NSMenu *)engineMenu;

@end

#endif
