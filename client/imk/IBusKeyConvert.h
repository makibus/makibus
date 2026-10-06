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

#ifndef __IBUS_KEY_CONVERT_H_
#define __IBUS_KEY_CONVERT_H_

#import <AppKit/AppKit.h>

#import <ibus.h>

#import "ibus-mac-keycode.h"

/* Convert the NSEvent modifier flags to the ibus modifier state.
 * The Command key is mapped to IBUS_MOD4_MASK (Super) like the
 * Windows/Super keys on the other platforms. */
NSUInteger ibus_state_from_modifier_flags (NSUInteger flags, BOOL release);

/* Resolve the ibus keyval of a key down event: the printable
 * characters follow the case of the modifiers like the X11 keyboard
 * mapping and the function keys are resolved from the keycode. */
guint ibus_keyval_from_event (NSEvent *event);

/* The ibus keyval and the keycode of a modifier key for the
 * NSFlagsChanged events, whose keyCode indicates the changed
 * modifier. */
BOOL ibus_modifier_event (NSEvent *event, guint *keyval, guint *keycode);

/* The NSEvent modifier flag bit of a modifier keycode. */
NSUInteger ibus_modifier_bit_of_keycode (unsigned short keycode);

#endif
