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

#ifndef __IBUS_MAC_KEYCODE_H_
#define __IBUS_MAC_KEYCODE_H_

#include <stdint.h>

/* XKB key codes, which are the Linux evdev key codes plus 8, indexed
 * by the macOS virtual key codes (kVK_ANSI_*) defined in
 * <IOKit/hidsystem/Events.h>.  The XKB key codes are expected by the
 * engines, e.g. the simple engine resolves the keyval from the
 * keycode with its XKB keymap table.  0 means the mapping is not
 * available. */
static const uint16_t ibus_mac_to_xkb_keycode[128] = {
    /* 0x00 */ 38,    /* A */
    /* 0x01 */ 39,    /* S */
    /* 0x02 */ 40,    /* D */
    /* 0x03 */ 41,    /* F */
    /* 0x04 */ 43,    /* H */
    /* 0x05 */ 42,    /* G */
    /* 0x06 */ 52,    /* Z */
    /* 0x07 */ 53,    /* X */
    /* 0x08 */ 54,    /* C */
    /* 0x09 */ 55,    /* V */
    /* 0x0a */ 0,
    /* 0x0b */ 56,    /* B */
    /* 0x0c */ 24,    /* Q */
    /* 0x0d */ 25,    /* W */
    /* 0x0e */ 26,    /* E */
    /* 0x0f */ 27,    /* R */
    /* 0x10 */ 29,    /* Y */
    /* 0x11 */ 28,    /* T */
    /* 0x12 */ 10,    /* 1 */
    /* 0x13 */ 11,    /* 2 */
    /* 0x14 */ 12,    /* 3 */
    /* 0x15 */ 13,    /* 4 */
    /* 0x16 */ 15,    /* 6 */
    /* 0x17 */ 14,    /* 5 */
    /* 0x18 */ 21,    /* = */
    /* 0x19 */ 0,
    /* 0x1a */ 18,    /* 9 */
    /* 0x1b */ 16,    /* 7 */
    /* 0x1c */ 20,    /* - */
    /* 0x1d */ 17,    /* 8 */
    /* 0x1e */ 19,    /* 0 */
    /* 0x1f */ 35,    /* ] */
    /* 0x20 */ 32,    /* O */
    /* 0x21 */ 30,    /* U */
    /* 0x22 */ 34,    /* [ */
    /* 0x23 */ 31,    /* I */
    /* 0x24 */ 33,    /* P */
    /* 0x25 */ 36,    /* Return */
    /* 0x26 */ 46,    /* L */
    /* 0x27 */ 44,    /* J */
    /* 0x28 */ 48,    /* ' */
    /* 0x29 */ 45,    /* K */
    /* 0x2a */ 47,    /* ; */
    /* 0x2b */ 51,    /* \ */
    /* 0x2c */ 59,    /* , */
    /* 0x2d */ 61,    /* / */
    /* 0x2e */ 57,    /* N */
    /* 0x2f */ 60,    /* . */
    /* 0x30 */ 23,    /* Tab */
    /* 0x31 */ 65,    /* Space */
    /* 0x32 */ 49,    /* ` */
    /* 0x33 */ 22,    /* Backspace */
    /* 0x34 */ 0,
    /* 0x35 */ 9,     /* Escape */
    /* 0x36 */ 134,   /* Right Command */
    /* 0x37 */ 133,   /* Left Command */
    /* 0x38 */ 50,    /* Left Shift */
    /* 0x39 */ 66,    /* CapsLock */
    /* 0x3a */ 64,    /* Left Option */
    /* 0x3b */ 37,    /* Left Control */
    /* 0x3c */ 62,    /* Right Shift */
    /* 0x3d */ 108,   /* Right Option */
    /* 0x3e */ 105,   /* Right Control */
    /* 0x3f */ 0,     /* Function */
    /* 0x40 */ 195,   /* F17 */
    /* 0x41 */ 91,    /* Keypad . */
    /* 0x42 */ 0,
    /* 0x43 */ 63,    /* Keypad * */
    /* 0x44 */ 0,
    /* 0x45 */ 86,    /* Keypad + */
    /* 0x46 */ 0,
    /* 0x47 */ 0,     /* Keypad Clear */
    /* 0x48 */ 0,     /* Volume Up */
    /* 0x49 */ 0,     /* Volume Down */
    /* 0x4a */ 0,     /* Mute */
    /* 0x4b */ 106,   /* Keypad / */
    /* 0x4c */ 104,   /* Keypad Enter */
    /* 0x4d */ 0,
    /* 0x4e */ 82,    /* Keypad - */
    /* 0x4f */ 197,   /* F18 */
    /* 0x50 */ 198,   /* F19 */
    /* 0x51 */ 125,   /* Keypad = */
    /* 0x52 */ 90,    /* Keypad 0 */
    /* 0x53 */ 87,    /* Keypad 1 */
    /* 0x54 */ 88,    /* Keypad 2 */
    /* 0x55 */ 89,    /* Keypad 3 */
    /* 0x56 */ 83,    /* Keypad 4 */
    /* 0x57 */ 84,    /* Keypad 5 */
    /* 0x58 */ 85,    /* Keypad 6 */
    /* 0x59 */ 79,    /* Keypad 7 */
    /* 0x5a */ 0,
    /* 0x5b */ 80,    /* Keypad 8 */
    /* 0x5c */ 81,    /* Keypad 9 */
    /* 0x5d */ 0,
    /* 0x5e */ 0,
    /* 0x5f */ 0,     /* JIS Keypad , */
    /* 0x60 */ 71,    /* F5 */
    /* 0x61 */ 72,    /* F6 */
    /* 0x62 */ 73,    /* F7 */
    /* 0x63 */ 69,    /* F3 */
    /* 0x64 */ 74,    /* F8 */
    /* 0x65 */ 75,    /* F9 */
    /* 0x66 */ 0,
    /* 0x67 */ 77,    /* F11 */
    /* 0x68 */ 0,
    /* 0x69 */ 191,   /* F13 */
    /* 0x6a */ 194,   /* F16 */
    /* 0x6b */ 0,
    /* 0x6c */ 0,
    /* 0x6d */ 76,    /* F10 */
    /* 0x6e */ 0,
    /* 0x6f */ 78,    /* F12 */
    /* 0x70 */ 0,
    /* 0x71 */ 192,   /* F14 */
    /* 0x72 */ 193,   /* F15 */
    /* 0x73 */ 151,   /* Help */
    /* 0x74 */ 110,   /* Home */
    /* 0x75 */ 112,   /* Page Up */
    /* 0x76 */ 119,   /* Forward Delete */
    /* 0x77 */ 70,    /* F4 */
    /* 0x78 */ 68,    /* F2 */
    /* 0x79 */ 67,    /* F1 */
    /* 0x7a */ 0,
    /* 0x7b */ 113,   /* Left */
    /* 0x7c */ 114,   /* Right */
    /* 0x7d */ 116,   /* Down */
    /* 0x7e */ 111,   /* Up */
    /* 0x7f */ 0,
};

/* Convert the NSEvent keyCode to the XKB keycode, i.e. the evdev
 * keycode plus 8. */
static inline uint32_t
ibus_mac_keycode_to_xkb (uint32_t mac_keycode)
{
    if (mac_keycode > 127)
        return 0;
    return ibus_mac_to_xkb_keycode[mac_keycode];
}

/* The XKB keycode of an ASCII character, for the test clients which
 * synthesize the key events from the plain text. */
static inline uint32_t
ibus_keycode_for_ascii (char ch)
{
    switch (ch) {
    case 'a': return 38;   case 's': return 39;
    case 'd': return 40;   case 'f': return 41;
    case 'h': return 43;   case 'g': return 42;
    case 'z': return 52;   case 'x': return 53;
    case 'c': return 54;   case 'v': return 55;
    case 'b': return 56;   case 'q': return 24;
    case 'w': return 25;   case 'e': return 26;
    case 'r': return 27;   case 'y': return 29;
    case 't': return 28;   case '1': return 10;
    case '2': return 11;   case '3': return 12;
    case '4': return 13;   case '6': return 15;
    case '5': return 14;   case '=': return 21;
    case '9': return 18;   case '7': return 16;
    case '-': return 20;   case '8': return 17;
    case '0': return 19;   case ']': return 35;
    case 'o': return 32;   case 'u': return 30;
    case '[': return 34;   case 'i': return 31;
    case 'p': return 33;   case '\n': return 36;
    case 'l': return 46;   case 'j': return 44;
    case '\'': return 48; case 'k': return 45;
    case ';': return 47;   case '\\': return 51;
    case ',': return 59;   case '/': return 61;
    case 'n': return 57;   case 'm': return 58;
    case '.': return 60;   case '\t': return 23;
    case ' ': return 65;   case '`': return 49;
    default: return 0;
    }
}

#endif
