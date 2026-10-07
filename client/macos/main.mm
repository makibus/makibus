/* -*- mode: C; c-basic-offset: 4; indent-tabs-mode: nil; -*- */
/* vim:set et sts=4: */
/* ibus - The Input Bus
 * Copyright (C) 2020,2026 Weixuan XIAO <veyx.shaw@gmail.com>
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
 * This is a test purpose client on macOS to send key events to the
 * ibus daemon and print out the engine outputs, e.g. the pre-edit and
 * committed texts.
 *
 * The real macOS integration should be implemented with an Input
 * Method Kit (IMK) input method, which converts the NSEvent key
 * events to the ibus key events with the macOS virtual keycode
 * conversion table below, and also renders the pre-edit text and
 * commits the text with the IMK APIs.
 */

#include <ibus.h>
#include <stdio.h>
#include <string.h>

/* XKB key codes, which are the Linux evdev key codes plus 8, indexed
 * by the macOS virtual key codes (kVK_ANSI_*) defined in
 * <IOKit/hidsystem/Events.h>.  The XKB key codes are expected by the
 * engines, e.g. the simple engine resolves the keyval from the
 * keycode with its XKB keymap table.  0 means the mapping is not
 * available. */
static const guint16 mac_to_xkb_keycode[128] = {
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
    /* 0x0a */ 0,    /* 0x0b */ 56,    /* B */
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
    /* 0x19 */ 0,    /* 0x1a */ 18,    /* 9 */
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
    /* 0x34 */ 0,    /* 0x35 */ 9,    /* Escape */
    /* 0x36 */ 134,    /* Right Command */
    /* 0x37 */ 133,    /* Left Command */
    /* 0x38 */ 50,    /* Left Shift */
    /* 0x39 */ 66,    /* CapsLock */
    /* 0x3a */ 64,    /* Left Option */
    /* 0x3b */ 37,    /* Left Control */
    /* 0x3c */ 62,    /* Right Shift */
    /* 0x3d */ 108,    /* Right Option */
    /* 0x3e */ 105,    /* Right Control */
    /* 0x3f */ 0,    /* Function */
    /* 0x40 */ 195,    /* F17 */
    /* 0x41 */ 91,    /* Keypad . */
    /* 0x42 */ 0,    /* 0x43 */ 63,    /* Keypad * */
    /* 0x44 */ 0,    /* 0x45 */ 86,    /* Keypad + */
    /* 0x46 */ 0,    /* 0x47 */ 0,    /* Keypad Clear */
    /* 0x48 */ 0,    /* Volume Up */
    /* 0x49 */ 0,    /* Volume Down */
    /* 0x4a */ 0,    /* Mute */
    /* 0x4b */ 106,    /* Keypad / */
    /* 0x4c */ 104,    /* Keypad Enter */
    /* 0x4d */ 0,    /* 0x4e */ 82,    /* Keypad - */
    /* 0x4f */ 197,    /* F18 */
    /* 0x50 */ 198,    /* F19 */
    /* 0x51 */ 125,    /* Keypad = */
    /* 0x52 */ 90,    /* Keypad 0 */
    /* 0x53 */ 87,    /* Keypad 1 */
    /* 0x54 */ 88,    /* Keypad 2 */
    /* 0x55 */ 89,    /* Keypad 3 */
    /* 0x56 */ 83,    /* Keypad 4 */
    /* 0x57 */ 84,    /* Keypad 5 */
    /* 0x58 */ 85,    /* Keypad 6 */
    /* 0x59 */ 79,    /* Keypad 7 */
    /* 0x5a */ 0,    /* 0x5b */ 80,    /* Keypad 8 */
    /* 0x5c */ 81,    /* Keypad 9 */
    /* 0x5d */ 0,    /* 0x5e */ 0,    /* 0x5f */ 0,    /* JIS Keypad , */
    /* 0x60 */ 71,    /* F5 */
    /* 0x61 */ 72,    /* F6 */
    /* 0x62 */ 73,    /* F7 */
    /* 0x63 */ 69,    /* F3 */
    /* 0x64 */ 74,    /* F8 */
    /* 0x65 */ 75,    /* F9 */
    /* 0x66 */ 0,    /* 0x67 */ 77,    /* F11 */
    /* 0x68 */ 0,    /* 0x69 */ 191,    /* F13 */
    /* 0x6a */ 194,    /* F16 */
    /* 0x6b */ 0,    /* 0x6c */ 0,    /* 0x6d */ 76,    /* F10 */
    /* 0x6e */ 0,    /* 0x6f */ 78,    /* F12 */
    /* 0x70 */ 0,    /* 0x71 */ 192,    /* F14 */
    /* 0x72 */ 193,    /* F15 */
    /* 0x73 */ 146,    /* Help */
    /* 0x74 */ 110,    /* Home */
    /* 0x75 */ 112,    /* Page Up */
    /* 0x76 */ 119,    /* Forward Delete */
    /* 0x77 */ 70,    /* F4 */
    /* 0x78 */ 68,    /* F2 */
    /* 0x79 */ 67,    /* F1 */
    /* 0x7a */ 0,    /* 0x7b */ 113,    /* Left */
    /* 0x7c */ 114,    /* Right */
    /* 0x7d */ 116,    /* Down */
    /* 0x7e */ 111,    /* Up */
    /* 0x7f */ 0,
};

static guint
_mac_keycode_for_ascii (gunichar ch)
{
    switch (g_unichar_tolower (ch)) {
    case 'a': return 0x00;  case 's': return 0x01;
    case 'd': return 0x02;  case 'f': return 0x03;
    case 'h': return 0x04;  case 'g': return 0x05;
    case 'z': return 0x06;  case 'x': return 0x07;
    case 'c': return 0x08;  case 'v': return 0x09;
    case 'b': return 0x0b;  case 'q': return 0x0c;
    case 'w': return 0x0d;  case 'e': return 0x0e;
    case 'r': return 0x0f;  case 'y': return 0x10;
    case 't': return 0x11;  case '1': return 0x12;
    case '2': return 0x13;  case '3': return 0x14;
    case '4': return 0x15;  case '6': return 0x16;
    case '5': return 0x17;  case '=': return 0x18;
    case '9': return 0x19;  case '7': return 0x1b;
    case '-': return 0x1c;  case '8': return 0x1d;
    case '0': return 0x1e;  case ']': return 0x1f;
    case 'o': return 0x20;  case 'u': return 0x21;
    case '[': return 0x22;  case 'i': return 0x23;
    case 'p': return 0x24;  case '\n': return 0x24; /* Return */
    case 'l': return 0x26;  case 'j': return 0x27;
    case '\'': return 0x28; case 'k': return 0x29;
    case ';': return 0x2a;  case '\\': return 0x2b;
    case ',': return 0x2c;  case '/': return 0x2d;
    case 'n': return 0x2e;  case '.': return 0x2f;
    case '\t': return 0x30; case ' ': return 0x31;
    case '`': return 0x32;  case 0x7f: return 0x33; /* Backspace */
    default: return 0;
    }
}

static IBusBus *_bus = NULL;
static IBusInputContext *_context = NULL;
static const gchar *_engine_name = "xkb:us::eng";
/* The standard input can reach EOF before the ibus-daemon connection
 * is established, e.g. when the input is piped. */
static gboolean _stdio_eof = FALSE;
/* The input lines are buffered until the input context is ready. */
static GQueue _pending_lines = G_QUEUE_INIT;

static void
_context_update_preedit_text_cb (IBusInputContext *context,
                                 IBusText         *text,
                                 gint              cursor_pos,
                                 gboolean          visible,
                                 gpointer          user_data)
{
    g_print ("preedit: \"%s\" cursor:%d visible:%d\n",
             text->text, cursor_pos, visible);
}

static void
_context_show_preedit_text_cb (IBusInputContext *context,
                               gpointer          user_data)
{
    g_print ("preedit shown\n");
}

static void
_context_hide_preedit_text_cb (IBusInputContext *context,
                               gpointer          user_data)
{
    g_print ("preedit hidden\n");
}

static void
_context_update_auxiliary_text_cb (IBusInputContext *context,
                                   IBusText         *text,
                                   gboolean          visible,
                                   gpointer          user_data)
{
    g_print ("auxiliary: \"%s\" visible:%d\n", text->text, visible);
}

static void
_context_update_lookup_table_cb (IBusInputContext *context,
                                 IBusLookupTable  *table,
                                 gboolean          visible,
                                 gpointer          user_data)
{
    guint n, i;

    if (!visible) {
        g_print ("candidates: hidden\n");
        return;
    }
    g_print ("candidates: ");
    n = ibus_lookup_table_get_number_of_candidates (table);
    for (i = 0; i < n; i++) {
        IBusText *text = ibus_lookup_table_get_candidate (table, i);
        g_print ("%d.%s ", i + 1, text->text);
    }
    g_print ("\n");
}

static void
_context_commit_text_cb (IBusInputContext *context,
                         IBusText         *text,
                         gpointer          user_data)
{
    g_print ("commit: \"%s\"\n", text->text);
}

static void
_context_forward_key_event_cb (IBusInputContext *context,
                               guint             keyval,
                               guint             keycode,
                               guint             state,
                               gpointer          user_data)
{
    g_print ("forward key event: keyval:%u keycode:%u state:%u\n",
             keyval, keycode, state);
}

static void
_bus_disconnected_cb (IBusBus *bus,
                      gpointer user_data)
{
    g_printerr ("Connection closed by ibus-daemon\n");
    g_clear_object (&_bus);
    ibus_quit ();
}

static void
_send_key_event (guint keyval,
                 guint keycode,
                 guint state)
{
    gboolean retval;

    if (_context == NULL)
        return;
    retval = ibus_input_context_process_key_event (_context,
                                                   keyval, keycode, state);
    g_debug ("key event keyval:%u(%c) keycode:%u state:%u handled:%d",
             keyval, keyval, keycode, state, retval);
    ibus_input_context_process_key_event (
            _context, keyval, keycode, state | IBUS_RELEASE_MASK);
}

static void
_send_unichar (gunichar ch)
{
    guint keyval;
    guint mac_keycode;
    guint keycode;

    /* Control characters have their own keysyms instead of the
     * 0x0100xxxx unicode mapping of ibus_unicode_to_keyval(). */
    switch (ch) {
    case '\n':  keyval = IBUS_KEY_Return;    break;
    case '\t':  keyval = IBUS_KEY_Tab;       break;
    case 0x7f:  keyval = IBUS_KEY_BackSpace; break;
    default:    keyval = ibus_unicode_to_keyval (ch);
    }
    mac_keycode = _mac_keycode_for_ascii (ch);
    keycode = (mac_keycode > 127) ?
            0 : mac_to_xkb_keycode[mac_keycode];
    _send_key_event (keyval, keycode, 0);
}

static gboolean
_quit_delayed_cb (gpointer user_data)
{
    ibus_quit ();
    return G_SOURCE_REMOVE;
}

/* The key events are processed asynchronously so wait for the engine
 * outputs before quitting. */
static void
_quit_delayed (void)
{
    g_timeout_add (500, _quit_delayed_cb, NULL);
}

static void
_process_line (const gchar *line)
{
    if (line[0] == '\0') {
        /* An empty line sends the Return key. */
        _send_unichar ('\n');
        return;
    }
    const gchar *p = line;
    while (*p != '\0') {
        gunichar ch = g_utf8_get_char (p);
        _send_unichar (ch);
        p = g_utf8_next_char (p);
    }
    /* Return commits the pre-edit text in the engine, except in the
     * panel pre-edit mode where the composition is kept on the
     * panel for the inspection (IBUS_MACOS_CLIENT_NO_RETURN=1). */
    if (g_getenv ("IBUS_MACOS_CLIENT_NO_RETURN") == NULL)
        _send_unichar ('\n');
}

static gboolean
_replay_pending_lines_cb (gpointer user_data)
{
    /* Replay the input lines which arrived before the connection.
     * This runs in an idle callback so that the focus-in is processed
     * by the ibus-daemon and the input context is enabled before the
     * key events are sent. */
    while (!g_queue_is_empty (&_pending_lines)) {
        gchar *line = (gchar *) g_queue_pop_head (&_pending_lines);
        g_strstrip (line);
        if (g_strcmp0 (line, "quit") == 0) {
            g_free (line);
            _quit_delayed ();
            return G_SOURCE_REMOVE;
        }
        _process_line (line);
        g_free (line);
    }

    if (_stdio_eof)
        _quit_delayed ();
    return G_SOURCE_REMOVE;
}

static void
_bus_connected_cb (IBusBus *bus,
                   gpointer user_data)
{
    _context = ibus_bus_create_input_context (_bus, "macos-test");
    if (_context == NULL) {
        g_printerr ("Failed to create an input context.\n");
        exit (EXIT_FAILURE);
    }

    g_signal_connect (_context, "commit-text",
                      G_CALLBACK (_context_commit_text_cb), NULL);
    g_signal_connect (_context, "forward-key-event",
                      G_CALLBACK (_context_forward_key_event_cb), NULL);
    g_signal_connect (_context, "update-preedit-text",
                      G_CALLBACK (_context_update_preedit_text_cb), NULL);
    g_signal_connect (_context, "show-preedit-text",
                      G_CALLBACK (_context_show_preedit_text_cb), NULL);
    g_signal_connect (_context, "hide-preedit-text",
                      G_CALLBACK (_context_hide_preedit_text_cb), NULL);
    g_signal_connect (_context, "update-auxiliary-text",
                      G_CALLBACK (_context_update_auxiliary_text_cb), NULL);
    g_signal_connect (_context, "update-lookup-table",
                      G_CALLBACK (_context_update_lookup_table_cb), NULL);

    /* Do not declare IBUS_CAP_LOOKUP_TABLE nor
     * IBUS_CAP_AUXILIARY_TEXT so that the ibus-daemon forwards the
     * candidates and the auxiliary texts to the panel.  With
     * IBUS_MACOS_CLIENT_PANEL_PREEDIT=1 also drop
     * IBUS_CAP_PREEDIT_TEXT, so the composition is forwarded to the
     * panel too and rendered in the candidate window header. */
    int caps = IBUS_CAP_FOCUS;
    if (g_getenv ("IBUS_MACOS_CLIENT_PANEL_PREEDIT") == NULL)
        caps |= IBUS_CAP_PREEDIT_TEXT;
    ibus_input_context_set_capabilities (_context, caps);
    /* ibus-daemon runs in the global engine mode by default and the
     * per-context SetEngine is rejected there.  Assign the global
     * engine instead and the focused input context will use it. */
    ibus_bus_set_global_engine (_bus, _engine_name);
    ibus_input_context_focus_in (_context);

    /* Wait for the asynchronous engine spawn and binding on the
     * daemon side, like the XPC test client, before the buffered
     * keys are replayed. */
    sleep (2);

    g_print ("Type characters followed by Enter to send them to the "
             "current engine, or type \"quit\" to exit.\n");

    g_timeout_add (500, _replay_pending_lines_cb, NULL);
}

static gboolean
_stdio_watch_cb (GIOChannel   *source,
                 GIOCondition  condition,
                 gpointer      user_data)
{
    gchar *line = NULL;
    gsize length = 0;
    GIOStatus status;

    if (condition & (G_IO_HUP | G_IO_ERR | G_IO_NVAL)) {
        g_debug ("stdio watch EOF, condition=%d, context=%p",
                 condition, _context);
        _stdio_eof = TRUE;
        if (_context != NULL)
            _quit_delayed ();
        else
            /* No connection yet: wait a bit before giving up. */
            g_timeout_add_seconds (5, _quit_delayed_cb, NULL);
        return FALSE;
    }

    status = g_io_channel_read_line (source, &line, &length, NULL, NULL);
    g_debug ("stdio read status=%d length=%u context=%p",
             status, (guint)length, _context);
    if (status == G_IO_STATUS_EOF) {
        g_free (line);
        _stdio_eof = TRUE;
        if (_context != NULL)
            _quit_delayed ();
        return FALSE;
    }
    if (status != G_IO_STATUS_NORMAL) {
        g_free (line);
        return TRUE;
    }

    if (_context == NULL) {
        /* Buffer the line until the input context is ready. */
        g_queue_push_tail (&_pending_lines, line);
        return TRUE;
    }

    g_strstrip (line);
    if (g_strcmp0 (line, "quit") == 0) {
        g_free (line);
        _quit_delayed ();
        return FALSE;
    }

    _process_line (line);
    g_free (line);
    return TRUE;
}

int
main (int    argc,
      char **argv)
{
    GIOChannel *channel;

    if (argc > 1)
        _engine_name = argv[1];

    ibus_init ();

    _bus = ibus_bus_new_async_client ();
    g_signal_connect (_bus, "connected",
                      G_CALLBACK (_bus_connected_cb), NULL);
    g_signal_connect (_bus, "disconnected",
                      G_CALLBACK (_bus_disconnected_cb), NULL);

    if (ibus_bus_is_connected (_bus))
        _bus_connected_cb (_bus, NULL);

    channel = g_io_channel_unix_new (fileno (stdin));
    g_io_channel_set_flags (channel, G_IO_FLAG_NONBLOCK, NULL);
    g_io_add_watch (channel,
                    (GIOCondition) (G_IO_IN | G_IO_HUP | G_IO_ERR),
                    _stdio_watch_cb, NULL);

    ibus_main ();

    g_io_channel_unref (channel);
    g_clear_object (&_context);
    g_clear_object (&_bus);

    return EXIT_SUCCESS;
}
