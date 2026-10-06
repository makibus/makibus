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

#ifndef __IBUS_KEYS_H_
#define __IBUS_KEYS_H_

#include <stdint.h>

/* The subset of the ibus keysyms and the modifier masks which the
 * IMK front end uses, so that the front end does not need to link
 * against libibus and can be distributed independently.  The values
 * follow the X11 keysym standard and ibustypes.h of the ibus
 * library. */

#define IBUS_KEY_a          0x061
#define IBUS_KEY_A          0x041
#define IBUS_KEY_U          0x055
#define IBUS_KEY_space      0x020
#define IBUS_KEY_BackSpace  0xff08
#define IBUS_KEY_Tab        0xff09
#define IBUS_KEY_Return     0xff0d
#define IBUS_KEY_Escape     0xff1b
#define IBUS_KEY_Delete     0xffff
#define IBUS_KEY_Home       0xff50
#define IBUS_KEY_Left       0xff51
#define IBUS_KEY_Up         0xff52
#define IBUS_KEY_Right      0xff53
#define IBUS_KEY_Down       0xff54
#define IBUS_KEY_Page_Up    0xff55
#define IBUS_KEY_Page_Down  0xff56
#define IBUS_KEY_End        0xff57
#define IBUS_KEY_Begin      0xff57
#define IBUS_KEY_Shift_L    0xffe1
#define IBUS_KEY_Shift_R    0xffe2
#define IBUS_KEY_Control_L  0xffe3
#define IBUS_KEY_Control_R  0xffe4
#define IBUS_KEY_Caps_Lock  0xffe5
#define IBUS_KEY_Shift_Lock 0xffe6
#define IBUS_KEY_Alt_L      0xffe9
#define IBUS_KEY_Alt_R      0xffea
#define IBUS_KEY_Super_L    0xffeb
#define IBUS_KEY_Super_R    0xffec

#define IBUS_SHIFT_MASK     (1u << 0)
#define IBUS_LOCK_MASK      (1u << 1)
#define IBUS_CONTROL_MASK   (1u << 2)
#define IBUS_MOD1_MASK      (1u << 3)
#define IBUS_MOD2_MASK      (1u << 4)
#define IBUS_MOD3_MASK      (1u << 5)
#define IBUS_MOD4_MASK      (1u << 6)
#define IBUS_MOD5_MASK      (1u << 7)
#define IBUS_RELEASE_MASK   (1u << 30)

/* Convert a Unicode character to an ibus keyval: the Latin-1
 * characters map to their code points like the X11 keysyms and the
 * other characters use the direct Unicode area (0x01000000 +
 * code point). */
static inline uint32_t
ibus_keyval_from_unicode (uint32_t wc)
{
    if (wc >= 0x20 && wc <= 0xff)
        return wc;
    return 0x01000000u | wc;
}

#endif
