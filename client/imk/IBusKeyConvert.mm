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

#import "IBusKeyConvert.h"

#import <Carbon/Carbon.h>
#include <ctype.h>

NSUInteger
ibus_state_from_modifier_flags (NSUInteger flags, BOOL release)
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

uint32_t
ibus_keyval_from_event (NSEvent *event)
{
    NSUInteger flags = event.modifierFlags &
            NSEventModifierFlagDeviceIndependentFlagsMask;
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
    if (ch < 0x80 && isprint ((int) ch))
        return (uint32_t) ch;
    return ibus_keyval_from_unicode ((uint32_t) ch);
}

BOOL
ibus_modifier_event (NSEvent *event, uint32_t *keyval, uint32_t *keycode)
{
    switch (event.keyCode) {
    case kVK_Shift:        *keyval = IBUS_KEY_Shift_L;   *keycode = 50;  break;
    case kVK_RightShift:   *keyval = IBUS_KEY_Shift_R;   *keycode = 62;  break;
    case kVK_Control:      *keyval = IBUS_KEY_Control_L; *keycode = 37;  break;
    case kVK_RightControl: *keyval = IBUS_KEY_Control_R; *keycode = 105; break;
    case kVK_Option:       *keyval = IBUS_KEY_Alt_L;     *keycode = 64;  break;
    case kVK_RightOption:  *keyval = IBUS_KEY_Alt_R;     *keycode = 108; break;
    case kVK_Command:      *keyval = IBUS_KEY_Super_L;   *keycode = 133; break;
    case kVK_RightCommand: *keyval = IBUS_KEY_Super_R;   *keycode = 134; break;
    case kVK_CapsLock:     *keyval = IBUS_KEY_Caps_Lock; *keycode = 66;  break;
    default:
        return FALSE;
    }
    return TRUE;
}

NSUInteger
ibus_modifier_bit_of_keycode (unsigned short keycode)
{
    switch (keycode) {
    case kVK_Shift:
    case kVK_RightShift:
        return NSShiftKeyMask;
    case kVK_Control:
    case kVK_RightControl:
        return NSControlKeyMask;
    case kVK_Option:
    case kVK_RightOption:
        return NSAlternateKeyMask;
    case kVK_Command:
    case kVK_RightCommand:
        return NSCommandKeyMask;
    case kVK_CapsLock:
        return NSAlphaShiftKeyMask;
    default:
        return 0;
    }
}
