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

#import "IBusInputController.h"

#import "IBusKeyConvert.h"

/* The keyboard modifier state of the process, which is updated with
 * the NSFlagsChanged events since the IMK front end does not receive
 * the modifier key down/up pairs as the key events. */
static NSUInteger _last_modifier_flags = 0;

@implementation IBusInputController

- (instancetype)initWithServer:(IMKServer *)server
                      delegate:(id)delegate
                        client:(id<IMKTextInput>)client
{
    self = [super initWithServer:server delegate:delegate client:client];
    if (self) {
        /* The delegate is set on activateServer: instead so that the
         * engine outputs are always routed to the focused
         * controller. */
    }
    return self;
}

/* Forward the modifier transitions as the individual ibus key
 * events.  The compose sequences like Ctrl+Shift+U rely on the
 * modifier press and release events. */
- (void)_handleFlagsChanged:(NSEvent *)event
{
    uint32_t keyval = 0;
    uint32_t keycode = 0;
    if (!ibus_modifier_event (event, &keyval, &keycode))
        return;

    NSUInteger flags = event.modifierFlags &
            NSEventModifierFlagDeviceIndependentFlagsMask;
    NSUInteger bit = ibus_modifier_bit_of_keycode (event.keyCode);
    BOOL pressed = (bit != 0 && (flags & bit) != 0 &&
                    (_last_modifier_flags & bit) == 0);
    BOOL released = (bit != 0 && (flags & bit) == 0 &&
                     (_last_modifier_flags & bit) != 0);
    _last_modifier_flags = flags;
    if (!pressed && !released)
        return;

    NSUInteger state = ibus_state_from_modifier_flags (flags, released);
    [[IBusXpcClient sharedClient] processKeyEventKeyval:keyval
                                                keycode:keycode
                                                  state:state
                                                   reply:^(BOOL handled) {}];
}

/* The heart of the input method: convert the NSEvent to the ibus key
 * event and ask the engine.  Return YES if the engine consumed the
 * event so that it is not delivered to the application. */
- (BOOL)handleEvent:(NSEvent *)event client:(id)sender
{
    if (event.type == NSEventTypeFlagsChanged) {
        [self _handleFlagsChanged:event];
        return NO;
    }
    if (event.type != NSEventTypeKeyDown)
        return NO;

    uint32_t keyval = ibus_keyval_from_event (event);
    uint32_t keycode = ibus_mac_keycode_to_xkb (event.keyCode);
    NSUInteger state = ibus_state_from_modifier_flags (
            event.modifierFlags, NO);
    /* The dead keys of the macOS layouts (e.g. Option+E) deliver an
     * empty characters string, which leaves keyval 0 while keycode
     * still names the physical key; sending such an event would
     * reach the engine with IBUS_KEY_VoidSymbol.  Pass the event to
     * the application, which composes the dead keys natively. */
    if (keyval == 0)
        return NO;

    __block BOOL result = NO;
    dispatch_semaphore_t done = dispatch_semaphore_create (0);
    BOOL sent = [[IBusXpcClient sharedClient]
            processKeyEventKeyval:keyval
                          keycode:keycode
                            state:state
                             reply:^(BOOL handled) {
        result = handled;
        dispatch_semaphore_signal (done);
    }];
    if (!sent) {
        /* The bridge is down; handle the key locally. */
        return NO;
    }
    dispatch_semaphore_wait (done,
            dispatch_time (DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC));

    /* IMK does not deliver the key up events; send the release
     * asynchronously right after the press like the test clients.
     * The autorepeat events are additional presses of an already
     * pressed key: only the first press gets the synthetic release
     * so that the engine sees one press-release pair per physical
     * keystroke instead of one pair per repeat. */
    if (!event.isARepeat) {
        [[IBusXpcClient sharedClient]
                processKeyEventKeyval:keyval
                              keycode:keycode
                                state:state | IBUS_RELEASE_MASK
                               reply:^(BOOL handled) {}];
    }

    if (result)
        [self _updateCursorLocation];
    return result;
}

- (void)_updateCursorLocation
{
    id<IMKTextInput> input = (id<IMKTextInput>) self.client;
    if (input == nil)
        return;
    /* firstRectForCharacterRange returns the global screen
     * coordinates with the top-left origin, which is the same
     * convention as the X11 cursor location of the ibus engines. */
    NSRect rect = [input firstRectForCharacterRange:
                          NSMakeRange ([input selectedRange].location, 0)
                                     actualRange:NULL];
    [[IBusXpcClient sharedClient] setCursorLocationX:(NSInteger) rect.origin.x
                                                   y:(NSInteger) rect.origin.y
                                               width:(NSInteger) rect.size.width
                                              height:(NSInteger) rect.size.height];
}

- (void)activateServer:(id)sender
{
    IBusXpcClient *xpc = [IBusXpcClient sharedClient];
    xpc.delegate = self;
    [xpc refreshEngines];
    [xpc focusIn];
    [xpc reset];
}

- (void)deactivateServer:(id)sender
{
    /* Clear the pre-edit text before losing the focus. */
    id<IMKTextInput> client = (id<IMKTextInput>) sender;
    [client setMarkedText:@""
            selectionRange:NSMakeRange (0, 0)
        replacementRange:NSMakeRange (NSNotFound, NSNotFound)];
    IBusXpcClient *xpc = [IBusXpcClient sharedClient];
    if (xpc.delegate == self)
        xpc.delegate = nil;
    [xpc focusOut];
}

- (NSMenu *)menu
{
    return [[IBusXpcClient sharedClient] engineMenu];
}

- (void)commitText:(NSString *)text
       client:(id<IMKTextInput>)client
{
    [client insertText:text
        replacementRange:NSMakeRange (NSNotFound, NSNotFound)];
}

#pragma mark IBusXpcClientDelegate

- (void)xpcClient:(IBusXpcClient *)client commitText:(NSString *)text
{
    id<IMKTextInput> input = (id<IMKTextInput>) self.client;
    if (input != nil)
        [self commitText:text client:input];
}

- (void)xpcClient:(IBusXpcClient *)client
        updatePreedit:(NSString *)text
              cursor:(NSUInteger)cursor
            visible:(BOOL)visible
{
    id<IMKTextInput> input = (id<IMKTextInput>) self.client;
    if (input == nil)
        return;
    if (!visible || text.length == 0) {
        [input setMarkedText:@""
                selectionRange:NSMakeRange (0, 0)
            replacementRange:NSMakeRange (NSNotFound, NSNotFound)];
        return;
    }
    /* The ibus pre-edit cursor is a character offset while the IMK
     * selection range is in the UTF-16 units of the string. */
    NSUInteger utf16_cursor = 0;
    for (NSUInteger i = 0;
         i < cursor && utf16_cursor < text.length; i++) {
        NSRange range = [text
                rangeOfComposedCharacterSequenceAtIndex:utf16_cursor];
        utf16_cursor = NSMaxRange (range);
    }
    [input setMarkedText:text
            selectionRange:NSMakeRange (utf16_cursor, 0)
        replacementRange:NSMakeRange (NSNotFound, NSNotFound)];
}

@end
