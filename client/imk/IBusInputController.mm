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

#import <Carbon/Carbon.h>
#import <ibus.h>

#import "ibus-mac-keycode.h"

/* Convert the NSEvent modifier flags to the ibus modifier state.
 * The Command key is mapped to IBUS_MOD4_MASK (Super) like the
 * Windows/Super keys on the other platforms. */
static NSUInteger
_ibus_state_from_modifier_flags (NSUInteger flags, BOOL release)
{
    NSUInteger state = 0;
    if (flags & NSShiftKeyMask)
        state |= IBUS_SHIFT_MASK;
    if (flags & NSAlphaShiftKeyMask)
        state |= IBUS_LOCK_MASK;
    if (flags & NSControlKeyMask)
        state |= IBUS_CONTROL_MASK;
    if (flags & NSAlternateKeyMask)
        state |= IBUS_MOD1_MASK;
    if (flags & NSCommandKeyMask)
        state |= IBUS_MOD4_MASK;
    if (release)
        state |= IBUS_RELEASE_MASK;
    return state;
}

/* Resolve the ibus keyval of a key down event: the printable
 * characters follow the case of the modifiers like the X11 keyboard
 * mapping and the function keys are resolved from the keycode. */
static guint
_ibus_keyval_from_event (NSEvent *event)
{
    NSUInteger flags = event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
    BOOL upper = (flags & NSShiftKeyMask) || (flags & NSAlphaShiftKeyMask);

    switch (event.keyCode) {
    case kVK_Return:        return IBUS_KEY_Return;
    case kVK_Tab:           return IBUS_KEY_Tab;
    case kVK_Space:         return IBUS_KEY_space;
    case kVK_Delete:        return IBUS_KEY_BackSpace;
    case kVK_ForwardDelete: return IBUS_KEY_Delete;
    case kVK_Escape:        return IBUS_KEY_Escape;
    case kVK_LeftArrow:     return IBUS_KEY_Left;
    case kVK_RightArrow:    return IBUS_KEY_Right;
    case kVK_UpArrow:       return IBUS_KEY_Up;
    case kVK_DownArrow:     return IBUS_KEY_Down;
    case kVK_Home:          return IBUS_KEY_Home;
    case kVK_End:           return IBUS_KEY_End;
    case kVK_PageUp:        return IBUS_KEY_Page_Up;
    case kVK_PageDown:      return IBUS_KEY_Page_Down;
    }

    NSString *characters = event.charactersIgnoringModifiers;
    if (characters.length != 1)
        return 0;
    unichar ch = [characters characterAtIndex:0];
    if (ch >= 'a' && ch <= 'z' && upper)
        ch = ch - 'a' + 'A';
    if (ch < 0x80 && g_ascii_isprint ((gchar) ch))
        return (guint) ch;
    return ibus_unicode_to_keyval ((gunichar) ch);
}

@implementation IBusInputController

- (instancetype)initWithServer:(IMKServer *)server
                      delegate:(id)delegate
                        client:(id<IMKTextInput>)client
{
    self = [super initWithServer:server delegate:delegate client:client];
    if (self) {
        IBusXpcClient *xpc = [IBusXpcClient sharedClient];
        xpc.delegate = self;
    }
    return self;
}

/* The heart of the input method: convert the NSEvent to the ibus key
 * event and ask the engine.  Return YES if the engine consumed the
 * event so that it is not delivered to the application. */
- (BOOL)handleEvent:(NSEvent *)event client:(id)sender
{
    if (event.type != NSEventTypeKeyDown)
        return NO;

    guint keyval = _ibus_keyval_from_event (event);
    guint keycode = ibus_mac_keycode_to_xkb (event.keyCode);
    NSUInteger state = _ibus_state_from_modifier_flags (
            event.modifierFlags, NO);
    if (keyval == 0 && keycode == 0)
        return NO;

    /* The engine outputs are applied in the IBusXpcClientDelegate
     * callbacks; the reply only decides the pass-through. */
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

    /* Send the release event asynchronously for the compose
     * sequences. */
    [[IBusXpcClient sharedClient]
            processKeyEventKeyval:keyval
                          keycode:keycode
                            state:state | IBUS_RELEASE_MASK
                             reply:^(BOOL handled) {}];

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
    [[IBusXpcClient sharedClient] focusIn];
    [[IBusXpcClient sharedClient] reset];
}

- (void)deactivateServer:(id)sender
{
    /* Clear the pre-edit text before losing the focus. */
    id<IMKTextInput> client = (id<IMKTextInput>) sender;
    [client setMarkedText:@""
            selectionRange:NSMakeRange (0, 0)
        replacementRange:NSMakeRange (NSNotFound, NSNotFound)];
    [[IBusXpcClient sharedClient] focusOut];
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
    [input setMarkedText:text
            selectionRange:NSMakeRange (cursor, 0)
        replacementRange:NSMakeRange (NSNotFound, NSNotFound)];
}

@end
