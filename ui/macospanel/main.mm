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
 * The native macOS panel for the ibus-daemon.
 *
 * The panel implements the org.freedesktop.IBus.Panel D-Bus service
 * with IBusPanelService and renders the candidate window and the
 * auxiliary text with the native AppKit APIs.  Clicking a candidate
 * sends the CandidateClicked signal back to the ibus-daemon.
 */

#include <ibus.h>

#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>

static IBusBus *_bus = NULL;
static IBusPanelService *_panel = NULL;
static NSApplication *_app = NULL;

/* The cursor location of the focused input context in the X11
 * top-left based coordinates, which is converted to the AppKit
 * bottom-left based coordinates when the candidates are shown. */
static NSRect _cursor_rect = { .origin = { 0, 0 }, .size = { 0, 0 } };

#pragma mark Candidate view

@interface CandidateView : NSView {
    NSArray<NSAttributedString *> *_candidates;
    NSArray<NSValue *> *_candidate_frames;
    NSAttributedString *_auxiliary;
    NSInteger _cursor_index;
}

- (void)setCandidates:(NSArray<NSAttributedString *> *)candidates
        cursorIndex:(NSInteger)index
        auxiliary:(NSAttributedString *)auxiliary;
- (NSInteger)candidateIndexAtPoint:(NSPoint)point;

@end

@implementation CandidateView

- (BOOL)isFlipped
{
    return YES;
}

- (void)setCandidates:(NSArray<NSAttributedString *> *)candidates
        cursorIndex:(NSInteger)index
        auxiliary:(NSAttributedString *)auxiliary
{
    _candidates = candidates;
    _cursor_index = index;
    _auxiliary = auxiliary;

    /* Layout the candidates in a single row and keep the frame of
     * each candidate for the mouse hit test and the highlight. */
    NSMutableArray *frames = [NSMutableArray array];
    CGFloat x = 8.0;
    for (NSAttributedString *candidate in candidates) {
        NSSize size = [candidate size];
        NSRect frame = NSMakeRect (x, 6.0, size.width + 12.0, size.height + 8.0);
        [frames addObject:[NSValue valueWithRect:frame]];
        x = NSMaxX (frame) + 4.0;
    }
    _candidate_frames = frames;

    [self setNeedsDisplay:YES];
}

- (NSInteger)candidateIndexAtPoint:(NSPoint)point
{
    NSUInteger i;
    for (i = 0; i < _candidate_frames.count; i++) {
        if (NSPointInRect (point, _candidate_frames[i].rectValue))
            return (NSInteger)i;
    }
    return -1;
}

- (void)drawRect:(NSRect)rect
{
    if (_candidates.count == 0 && _auxiliary == nil)
        return;

    [[NSColor textBackgroundColor] setFill];
    NSRect bounds = [self bounds];
    NSBezierPath *path =
            [NSBezierPath bezierPathWithRoundedRect:bounds
                                         xRadius:8.0
                                         yRadius:8.0];
    [path fill];

    if (_candidates.count > 0 &&
        _cursor_index >= 0 && _cursor_index < (NSInteger)_candidates.count) {
        [[NSColor selectedTextBackgroundColor] setFill];
        NSRect frame = _candidate_frames[_cursor_index].rectValue;
        NSBezierPath *highlight =
                [NSBezierPath bezierPathWithRoundedRect:frame
                                             xRadius:4.0
                                             yRadius:4.0];
        [highlight fill];
    }

    NSUInteger i;
    for (i = 0; i < _candidates.count; i++) {
        NSRect frame = _candidate_frames[i].rectValue;
        NSPoint origin = NSMakePoint (frame.origin.x + 6.0,
                                      frame.origin.y + 4.0);
        [_candidates[i] drawAtPoint:origin];
    }

    if (_auxiliary != nil) {
        CGFloat y = (CGFloat)[self candidatesBottomY];
        [_auxiliary drawAtPoint:NSMakePoint (8.0, y)];
    }
}

- (CGFloat)candidatesBottomY
{
    if (_candidate_frames.count == 0)
        return 6.0;
    return NSMaxY (_candidate_frames[0].rectValue) + 6.0;
}

- (void)mouseDown:(NSEvent *)event
{
    NSPoint point = [self convertPoint:[event locationInWindow]
                              fromView:nil];
    NSInteger index = [self candidateIndexAtPoint:point];
    if (index < 0)
        return;
    if (_panel != NULL) {
        ibus_panel_service_candidate_clicked (_panel, (guint)index, 1, 0);
    }
}

- (NSSize)intrinsicContentSize
{
    if (_candidates.count == 0 && _auxiliary == nil)
        return NSMakeSize (0, 0);

    CGFloat width = 16.0;
    CGFloat height = 0.0;
    if (_candidate_frames.count > 0) {
        width = NSMaxX (_candidate_frames[_candidate_frames.count - 1]
                        .rectValue) + 8.0;
        height = NSMaxY (_candidate_frames[0].rectValue);
    }
    if (_auxiliary != nil)
        height += _auxiliary.size.height + 6.0;
    return NSMakeSize (width, height + 6.0);
}

@end

#pragma mark Candidate window

@interface CandidateWindow : NSObject {
    NSPanel *_window;
    CandidateView *_view;
}

- (void)showCandidates:(NSArray<NSAttributedString *> *)candidates
         cursorIndex:(NSInteger)index
         auxiliary:(NSAttributedString *)auxiliary
         around:(NSRect)cursorRect;
- (void)hide;

@end

@implementation CandidateWindow

- (id)init
{
    self = [super init];
    if (self) {
        _window = [[NSPanel alloc]
                initWithContentRect:NSMakeRect (0, 0, 200, 40)
                          styleMask:NSWindowStyleMaskBorderless |
                                    NSWindowStyleMaskNonactivatingPanel
                            backing:NSBackingStoreBuffered
                              defer:NO];
        [_window setLevel:NSPopUpMenuWindowLevel];
        [_window setHasShadow:YES];
        [_window setOpaque:NO];
        [_window setBackgroundColor:[NSColor clearColor]];
        [_window setHidesOnDeactivate:NO];

        _view = [[CandidateView alloc] initWithFrame:NSMakeRect (0, 0, 200, 40)];
        [_window setContentView:_view];
    }
    return self;
}

- (void)showCandidates:(NSArray<NSAttributedString *> *)candidates
         cursorIndex:(NSInteger)index
         auxiliary:(NSAttributedString *)auxiliary
         around:(NSRect)cursorRect
{
    NSScreen *screen = [NSScreen mainScreen];
    if (screen == nil)
        return;

    [_view setCandidates:candidates cursorIndex:index auxiliary:auxiliary];

    NSSize size = [_view intrinsicContentSize];
    if (size.width <= 0 || size.height <= 0) {
        [self hide];
        return;
    }

    /* Convert the X11 top-left based cursor rectangle to the AppKit
     * bottom-left based coordinates. */
    CGFloat screenHeight =
            screen.frame.origin.y + screen.frame.size.height;
    CGFloat x = cursorRect.origin.x;
    CGFloat y = screenHeight - (cursorRect.origin.y + cursorRect.size.height)
                - size.height - 4.0;

    /* Show the candidates above the cursor rectangle if there is no
     * enough space below. */
    if (y < screen.visibleFrame.origin.y)
        y = screenHeight - cursorRect.origin.y + 4.0;

    /* Clamp the candidates within the screen. */
    if (x + size.width > NSMaxX (screen.visibleFrame))
        x = NSMaxX (screen.visibleFrame) - size.width;
    if (x < screen.visibleFrame.origin.x)
        x = screen.visibleFrame.origin.x;

    [_window setFrame:NSMakeRect (x, y, size.width, size.height)
              display:YES];
    [_window orderFront:nil];
}

- (void)hide
{
    [_window orderOut:nil];
}

@end

static CandidateWindow *_candidate_window = nil;

#pragma mark Panel service callbacks

static void
_show_lookup_table (IBusLookupTable *table)
{
    g_return_if_fail (table != NULL);

    guint n = ibus_lookup_table_get_number_of_candidates (table);
    guint page_size = ibus_lookup_table_get_page_size (table);
    guint cursor_pos = ibus_lookup_table_get_cursor_pos (table);
    guint page = (page_size > 0) ? cursor_pos / page_size : 0;
    guint first = page * page_size;
    guint i;

    NSDictionary *attributes = @{
        NSFontAttributeName: [NSFont systemFontOfSize:14.0],
        NSForegroundColorAttributeName: [NSColor textColor],
    };

    NSMutableArray *candidates = [NSMutableArray array];
    for (i = first; i < n && i < first + page_size; i++) {
        IBusText *text = ibus_lookup_table_get_candidate (table, i);
        IBusText *label_text = ibus_lookup_table_get_label (table, i);
        NSString *label = (label_text != NULL && label_text->text[0] != '\0') ?
                [NSString stringWithUTF8String:label_text->text] :
                [NSString stringWithFormat:@"%u.", (guint)(i - first + 1)];
        NSMutableAttributedString *candidate =
                [[NSMutableAttributedString alloc] initWithString:label
                                                        attributes:attributes];
        NSAttributedString *candidate_text =
                [[NSAttributedString alloc]
                        initWithString:[NSString stringWithUTF8String:
                                                 text->text]
                          attributes:attributes];
        [candidate appendAttributedString:candidate_text];
        [candidates addObject:candidate];
    }

    [_candidate_window showCandidates:candidates
                         cursorIndex:(page_size > 0) ?
                                 (cursor_pos % page_size) : 0
                         auxiliary:nil
                         around:_cursor_rect];
}

static void
_update_lookup_table_cb (IBusPanelService *panel,
                         IBusLookupTable  *table,
                         gboolean          visible,
                         gpointer          user_data)
{
    if (visible && table != NULL)
        _show_lookup_table (table);
    else
        [_candidate_window hide];
}

static void
_show_lookup_table_cb (IBusPanelService *panel,
                       gpointer          user_data)
{
    /* The lookup table was already rendered in the update signal. */
}

static void
_hide_lookup_table_cb (IBusPanelService *panel,
                       gpointer          user_data)
{
    [_candidate_window hide];
}

static void
_set_cursor_location_cb (IBusPanelService *panel,
                         gint              x,
                         gint              y,
                         gint              w,
                         gint              h,
                         gpointer          user_data)
{
    _cursor_rect = NSMakeRect (x, y, w, h);
}

static void
_update_auxiliary_text_cb (IBusPanelService *panel,
                           IBusText         *text,
                           gboolean          visible,
                           gpointer          user_data)
{
    if (!visible)
        return;
    NSDictionary *attributes = @{
        NSFontAttributeName: [NSFont systemFontOfSize:12.0],
        NSForegroundColorAttributeName: [NSColor secondaryLabelColor],
    };
    NSAttributedString *auxiliary =
            [[NSAttributedString alloc]
                    initWithString:[NSString stringWithUTF8String:text->text]
                      attributes:attributes];
    /* TODO: Show the auxiliary text with the candidates. */
    g_debug ("auxiliary text: %s", text->text);
}

static void
_focus_in_cb (IBusPanelService *panel,
              const gchar      *input_context_path,
              gpointer          user_data)
{
    g_debug ("focus in %s", input_context_path);
}

static void
_focus_out_cb (IBusPanelService *panel,
               const gchar      *input_context_path,
               gpointer          user_data)
{
    g_debug ("focus out %s", input_context_path);
    [_candidate_window hide];
}

static void
_state_changed_cb (IBusPanelService *panel,
                   gpointer          user_data)
{
    [_candidate_window hide];
}

static void
_register_panel_service (void)
{
    if (_panel != NULL)
        return;

    GDBusConnection *connection = ibus_bus_get_connection (_bus);
    if (connection == NULL)
        return;

    _panel = ibus_panel_service_new (connection);
    g_object_ref_sink (_panel);

    g_signal_connect (_panel, "update-lookup-table",
                      G_CALLBACK (_update_lookup_table_cb), NULL);
    g_signal_connect (_panel, "show-lookup-table",
                      G_CALLBACK (_show_lookup_table_cb), NULL);
    g_signal_connect (_panel, "hide-lookup-table",
                      G_CALLBACK (_hide_lookup_table_cb), NULL);
    g_signal_connect (_panel, "set-cursor-location",
                      G_CALLBACK (_set_cursor_location_cb), NULL);
    g_signal_connect (_panel, "update-auxiliary-text",
                      G_CALLBACK (_update_auxiliary_text_cb), NULL);
    g_signal_connect (_panel, "focus-in",
                      G_CALLBACK (_focus_in_cb), NULL);
    g_signal_connect (_panel, "focus-out",
                      G_CALLBACK (_focus_out_cb), NULL);
    g_signal_connect (_panel, "state-changed",
                      G_CALLBACK (_state_changed_cb), NULL);
}

static void
_bus_connected_cb (IBusBus *bus,
                   gpointer user_data)
{
    _register_panel_service ();
}

static void
_bus_disconnected_cb (IBusBus *bus,
                      gpointer user_data)
{
    g_debug ("Connection closed by ibus-daemon");
    [_candidate_window hide];
    [_app terminate:_app];
}

#pragma mark GLib main loop integration

/* Run the GLib main loop in the AppKit main run loop with a timer so
 * that the D-Bus signal callbacks are always invoked on the main
 * thread and the AppKit APIs can be called directly. */
static void
_glib_iteration (CFRunLoopTimerRef timer,
                 void             *info)
{
    while (g_main_context_pending (NULL))
        g_main_context_iteration (NULL, FALSE);
}

int
main (int    argc,
      char **argv)
{
    ibus_init ();

    _bus = ibus_bus_new_async_client ();
    g_signal_connect (_bus, "connected",
                      G_CALLBACK (_bus_connected_cb), NULL);
    g_signal_connect (_bus, "disconnected",
                      G_CALLBACK (_bus_disconnected_cb), NULL);

    _candidate_window = [[CandidateWindow alloc] init];

    CFRunLoopTimerContext context = { 0, NULL, NULL, NULL, NULL };
    CFRunLoopTimerRef timer = CFRunLoopTimerCreate (
            kCFAllocatorDefault, 0, 0.01, 0, 0, _glib_iteration, &context);
    CFRunLoopAddTimer (CFRunLoopGetMain (), timer, kCFRunLoopCommonModes);

    @autoreleasepool {
        _app = [NSApplication sharedApplication];
        [_app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        if (ibus_bus_is_connected (_bus))
            _bus_connected_cb (_bus, NULL);
        [_app run];
    }

    CFRunLoopRemoveTimer (CFRunLoopGetMain (), timer, kCFRunLoopCommonModes);
    CFRelease (timer);

    g_clear_object (&_panel);
    g_clear_object (&_bus);

    return EXIT_SUCCESS;
}
