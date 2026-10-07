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
 * with IBusPanelService and renders the candidate window with the
 * native AppKit APIs: the lookup table orientation of the engine is
 * honored (the vertical layout of the Chinese engines), the mouse
 * wheel turns the pages, the candidates are highlighted on hover,
 * the page number and the auxiliary text (e.g. the pinyin hint of
 * rime) are displayed, and the window follows the cursor location on
 * the screen which contains the text cursor.  Clicking a candidate
 * or the mouse wheel sends the CandidateClicked / PageUp / PageDown
 * signals back to the ibus-daemon.
 */

#include <ibus.h>

#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>

/* The launchd Mach service name of the bridge is not used here; the
 * panel connects to the ibus-daemon through the address file. */

static IBusBus *_bus = NULL;
static IBusPanelService *_panel = NULL;
static NSApplication *_app = NULL;

/* The cursor location of the focused input context in the X11
 * top-left based coordinates, which is converted to the AppKit
 * bottom-left based coordinates when the candidates are shown. */
static NSRect _cursor_rect = { .origin = { 0, 0 }, .size = { 0, 0 } };

/* The last lookup table, the auxiliary text and the pre-edit text,
 * kept for the partial updates: the engines send them as the
 * separate signals and the window renders them together. */
static IBusLookupTable *_last_table = NULL;
static NSAttributedString *_auxiliary = nil;
static NSAttributedString *_preedit = nil;
static NSUInteger _preedit_cursor = 0;
static BOOL _preedit_visible = FALSE;

/* The engines which do not set the orientation of the lookup table
 * (e.g. ibus-rime) get the horizontal default; the users of the
 * vertical Chinese panels can force the vertical layout with
 * IBUS_MACOSPANEL_VERTICAL=1. */
static BOOL _force_vertical = NO;

static void _rerender (void);

#pragma mark Candidate view

@interface CandidateView : NSView {
    NSArray<NSAttributedString *> *_candidates;
    NSArray<NSValue *> *_candidate_frames;
    NSAttributedString *_auxiliary;
    NSString *_page_info;
    NSInteger _cursor_index;
    NSInteger _hover_index;
    BOOL _vertical;
    CGFloat _footer_height;
    CGFloat _header_height;
    NSAttributedString *_preedit;
    NSUInteger _preedit_cursor;
    void (^_page_handler) (NSInteger delta);
}

- (void)setCandidates:(NSArray<NSAttributedString *> *)candidates
         cursorIndex:(NSInteger)index
           auxiliary:(NSAttributedString * _Nullable)auxiliary
             pageInfo:(NSString * _Nullable)page_info
             vertical:(BOOL)vertical
         pageHandler:(void (^ _Nullable) (NSInteger delta))handler;
- (void)setPreedit:(NSAttributedString * _Nullable)preedit
             cursor:(NSUInteger)cursor;
- (NSInteger)candidateIndexAtPoint:(NSPoint)point;

@end

@implementation CandidateView

- (BOOL)isFlipped
{
    return YES;
}

- (BOOL)acceptsMouseMovedEvents
{
    return YES;
}

- (void)setCandidates:(NSArray<NSAttributedString *> *)candidates
         cursorIndex:(NSInteger)index
           auxiliary:(NSAttributedString *)auxiliary
             pageInfo:(NSString * _Nullable)page_info
             vertical:(BOOL)vertical
         pageHandler:(void (^ _Nullable) (NSInteger delta))handler
{
    _candidates = candidates;
    _cursor_index = index;
    _auxiliary = auxiliary;
    _page_info = page_info;
    _vertical = vertical;
    _hover_index = -1;
    _page_handler = handler;

    /* The pre-edit text is rendered in the header above the
     * candidates, e.g. the composition of the engines which do not
     * embed it in the client. */
    _header_height = 0.0;
    if (_preedit != nil)
        _header_height = _preedit.size.height + 8.0;

    /* Keep the frame of each candidate for the mouse hit test, the
     * highlight and the hover. */
    NSMutableArray *frames = [NSMutableArray array];
    if (vertical) {
        /* One candidate per row. */
        CGFloat row_height = 0.0;
        CGFloat row_width = 0.0;
        for (NSAttributedString *candidate in candidates) {
            NSSize size = [candidate size];
            row_height = MAX (row_height, size.height + 8.0);
            row_width = MAX (row_width, size.width + 12.0);
        }
        CGFloat y = 6.0 + _header_height;
        for (NSUInteger i = 0; i < candidates.count; i++) {
            [frames addObject:
                    [NSValue valueWithRect:
                            NSMakeRect (8.0, y, row_width, row_height)]];
            y += row_height + 2.0;
        }
    }
    else {
        /* A single row. */
        CGFloat x = 8.0;
        CGFloat y = 6.0 + _header_height;
        for (NSAttributedString *candidate in candidates) {
            NSSize size = [candidate size];
            NSRect frame = NSMakeRect (x, y,
                                       size.width + 12.0,
                                       size.height + 8.0);
            [frames addObject:[NSValue valueWithRect:frame]];
            x = NSMaxX (frame) + 4.0;
        }
    }
    _candidate_frames = frames;

    /* The footer row holds the auxiliary text on the left and the
     * page number on the right. */
    _footer_height = 0.0;
    if (auxiliary != nil)
        _footer_height = MAX (_footer_height,
                              auxiliary.size.height + 4.0);
    if (page_info != nil)
        _footer_height = MAX (_footer_height, 16.0);

    [self setNeedsDisplay:YES];
}

- (void)setPreedit:(NSAttributedString * _Nullable)preedit
             cursor:(NSUInteger)cursor
{
    _preedit = preedit;
    _preedit_cursor = cursor;
    _header_height = (preedit != nil) ? preedit.size.height + 8.0 : 0.0;
    [self setNeedsDisplay:YES];
}

/* The caret position of the pre-edit cursor in the rendered text
 * width, converting the character offset to the rendering width. */
- (CGFloat)_preeditCursorX:(NSAttributedString *)preedit
{
    NSString *string = preedit.string;
    NSUInteger utf16 = 0;
    for (NSUInteger i = 0;
         i < _preedit_cursor && utf16 < string.length; i++) {
        NSRange range = [string
                rangeOfComposedCharacterSequenceAtIndex:utf16];
        utf16 = NSMaxRange (range);
    }
    __block NSDictionary *attrs = @{};
    [preedit enumerateAttributesInRange:
            NSMakeRange (0, MIN (utf16, preedit.length))
                          options:0
                       usingBlock:^(NSDictionary *a, NSRange r, BOOL *stop) {
        attrs = a;
    }];
    NSAttributedString *head =
            [[NSAttributedString alloc] initWithString:
                    [string substringToIndex:utf16]
                                             attributes:attrs];
    return head.size.width;
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
    if (_candidates.count == 0)
        return;

    [[NSColor textBackgroundColor] setFill];
    NSRect bounds = [self bounds];
    NSBezierPath *path =
            [NSBezierPath bezierPathWithRoundedRect:bounds
                                         xRadius:8.0
                                         yRadius:8.0];
    [path fill];

    /* The hover highlight under the cursor highlight. */
    if (_hover_index >= 0 && _hover_index < (NSInteger)_candidates.count &&
        _hover_index != _cursor_index) {
        NSColor *selection = [NSColor selectedTextBackgroundColor];
        NSColor *hover_color =
                [selection colorWithAlphaComponent:0.35];
        [hover_color setFill];
        NSRect frame = _candidate_frames[_hover_index].rectValue;
        NSBezierPath *hover =
                [NSBezierPath bezierPathWithRoundedRect:frame
                                             xRadius:4.0
                                             yRadius:4.0];
        [hover fill];
    }

    if (_cursor_index >= 0 &&
        _cursor_index < (NSInteger)_candidates.count) {
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
        [_candidates[i] drawAtPoint:NSMakePoint (frame.origin.x + 6.0,
                                                 frame.origin.y + 4.0)];
    }

    if (_header_height > 0.0 && _preedit != nil) {
        NSPoint origin = NSMakePoint (8.0, 4.0);
        [_preedit drawAtPoint:origin];
        /* The composition caret at the pre-edit cursor position. */
        CGFloat caret_x = origin.x + [self _preeditCursorX:_preedit];
        NSRect caret = NSMakeRect (caret_x, origin.y - 1.0,
                                   1.5, _preedit.size.height + 2.0);
        [[NSColor textColor] setFill];
        NSRectFillUsingOperation (caret, NSCompositingOperationSourceOver);
    }

    if (_footer_height > 0.0) {
        CGFloat footer_y = NSMaxY (
                _candidate_frames[_candidate_frames.count - 1]
                        .rectValue) + 2.0;
        if (_auxiliary != nil)
            [_auxiliary drawAtPoint:NSMakePoint (8.0, footer_y + 2.0)];
        if (_page_info != nil) {
            NSDictionary *attrs = @{
                NSFontAttributeName: [NSFont systemFontOfSize:10.0],
                NSForegroundColorAttributeName: [NSColor tertiaryLabelColor],
            };
            NSAttributedString *page =
                    [[NSAttributedString alloc] initWithString:_page_info
                                                     attributes:attrs];
            CGFloat x = NSMaxX (bounds) - page.size.width - 8.0;
            [page drawAtPoint:NSMakePoint (x, footer_y + 2.0)];
        }
    }
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

- (void)mouseMoved:(NSEvent *)event
{
    NSPoint point = [self convertPoint:[event locationInWindow]
                              fromView:nil];
    NSInteger index = [self candidateIndexAtPoint:point];
    if (index != _hover_index) {
        _hover_index = index;
        [self setNeedsDisplay:YES];
    }
}

- (void)mouseExited:(NSEvent *)event
{
    if (_hover_index != -1) {
        _hover_index = -1;
        [self setNeedsDisplay:YES];
    }
}

/* The mouse wheel turns the pages of the lookup table. */
- (void)scrollWheel:(NSEvent *)event
{
    if (_page_handler == nil)
        return;
    CGFloat delta = _vertical ? event.scrollingDeltaY
                              : event.scrollingDeltaX;
    if (delta == 0.0)
        delta = _vertical ? event.scrollingDeltaX : event.scrollingDeltaY;
    if (delta < 0.0)
        _page_handler (1);
    else if (delta > 0.0)
        _page_handler (-1);
}

- (void)viewDidMoveToWindow
{
    /* The tracking works although the panel does not take the focus
     * (NSTrackingActiveAlways). */
    for (NSTrackingArea *area in self.trackingAreas)
        [self removeTrackingArea:area];
    NSTrackingAreaOptions options =
            NSTrackingMouseMoved | NSTrackingMouseEnteredAndExited |
            NSTrackingActiveAlways | NSTrackingInVisibleRect;
    [self addTrackingArea:
            [[NSTrackingArea alloc] initWithRect:self.bounds
                                         options:options
                                           owner:self
                                        userInfo:nil]];
}

- (NSSize)intrinsicContentSize
{
    if (_candidates.count == 0)
        return NSMakeSize (0, 0);

    CGFloat width;
    CGFloat height;
    if (_vertical) {
        NSRect last = _candidate_frames[_candidate_frames.count - 1]
                .rectValue;
        width = NSMaxX (last) + 8.0;
        height = NSMaxY (last) + 2.0;
    }
    else {
        width = NSMaxX (_candidate_frames[_candidate_frames.count - 1]
                        .rectValue) + 8.0;
        height = NSMaxY (_candidate_frames[0].rectValue) + 2.0;
    }
    height += _header_height + _footer_height;
    return NSMakeSize (width, height + 4.0);
}

@end

#pragma mark Candidate window

@interface CandidateWindow : NSObject {
    NSPanel *_window;
    CandidateView *_view;
}

- (void)showCandidates:(NSArray<NSAttributedString *> *)candidates
          cursorIndex:(NSInteger)index
            auxiliary:(NSAttributedString * _Nullable)auxiliary
              pageInfo:(NSString * _Nullable)page_info
              vertical:(BOOL)vertical
          pageHandler:(void (^ _Nullable) (NSInteger delta))handler
               around:(NSRect)cursorRect;
- (void)showPreedit:(NSAttributedString * _Nullable)preedit
             cursor:(NSUInteger)cursor
             vertical:(BOOL)vertical
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
        [_window setIgnoresMouseEvents:NO];

        _view = [[CandidateView alloc] initWithFrame:NSMakeRect (0, 0, 200, 40)];
        [_window setContentView:_view];
    }
    return self;
}

/* The screen which contains the text cursor, so that the candidates
 * follow the cursor across the multiple displays. */
+ (NSScreen *)screenForCursorRect:(NSRect)cursor_rect
{
    /* The cursor rect is in the X11 top-left based global
     * coordinates; NSMouseInRect needs the flipped coordinates, so
     * just compare the points directly. */
    NSPoint center = NSMakePoint (NSMidX (cursor_rect),
                                  NSMidY (cursor_rect));
    for (NSScreen *screen in [NSScreen screens]) {
        if (NSMouseInRect (center, screen.frame, NO))
            return screen;
    }
    return [NSScreen mainScreen];
}

- (void)showCandidates:(NSArray<NSAttributedString *> *)candidates
          cursorIndex:(NSInteger)index
            auxiliary:(NSAttributedString * _Nullable)auxiliary
              pageInfo:(NSString * _Nullable)page_info
              vertical:(BOOL)vertical
          pageHandler:(void (^ _Nullable) (NSInteger delta))handler
               around:(NSRect)cursorRect
{
    NSScreen *screen = [CandidateWindow screenForCursorRect:cursorRect];
    if (screen == nil)
        return;

    [_view setCandidates:candidates
             cursorIndex:index
               auxiliary:auxiliary
                 pageInfo:page_info
                 vertical:vertical
             pageHandler:handler];
    [_view setPreedit:_preedit cursor:_preedit_cursor];

    NSSize size = [_view intrinsicContentSize];
    if (size.width <= 0 || size.height <= 0) {
        [self hide];
        return;
    }

    /* Convert the X11 top-left based cursor rectangle to the AppKit
     * bottom-left based coordinates of the screen. */
    CGFloat screen_top = NSMaxY (screen.frame);
    CGFloat x = cursorRect.origin.x - screen.frame.origin.x;
    CGFloat y = screen_top - NSMaxY (cursorRect) - size.height - 4.0;

    /* Show the candidates above the cursor rectangle if there is no
     * enough space below. */
    if (y < screen.visibleFrame.origin.y)
        y = screen_top - cursorRect.origin.y + 4.0;

    /* Clamp the candidates within the screen. */
    x += screen.frame.origin.x;
    if (x + size.width > NSMaxX (screen.visibleFrame))
        x = NSMaxX (screen.visibleFrame) - size.width;
    if (x < screen.visibleFrame.origin.x)
        x = screen.visibleFrame.origin.x;

    [_window setFrame:NSMakeRect (x, y, size.width, size.height)
              display:YES];
    [_window orderFront:nil];
}

- (void)showPreedit:(NSAttributedString * _Nullable)preedit
             cursor:(NSUInteger)cursor
             vertical:(BOOL)vertical
               around:(NSRect)cursorRect
{
    NSScreen *screen = [CandidateWindow screenForCursorRect:cursorRect];
    if (screen == nil || preedit == nil) {
        [self hide];
        return;
    }
    [_view setCandidates:@[]
             cursorIndex:-1
               auxiliary:nil
                 pageInfo:nil
                 vertical:vertical
             pageHandler:nil];
    [_view setPreedit:preedit cursor:cursor];

    NSSize size = [_view intrinsicContentSize];
    if (size.width <= 0 || size.height <= 0) {
        [self hide];
        return;
    }

    CGFloat screen_top = NSMaxY (screen.frame);
    CGFloat x = cursorRect.origin.x - screen.frame.origin.x;
    CGFloat y = screen_top - NSMaxY (cursorRect) - size.height - 4.0;
    if (y < screen.visibleFrame.origin.y)
        y = screen_top - cursorRect.origin.y + 4.0;
    x += screen.frame.origin.x;
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
_page (NSInteger delta)
{
    if (_panel == NULL)
        return;
    g_debug ("page %ld", (long) delta);
    if (delta > 0)
        ibus_panel_service_page_down (_panel);
    else
        ibus_panel_service_page_up (_panel);
}

static void
_show_lookup_table (IBusLookupTable *table)
{
    g_return_if_fail (table != NULL);

    guint n = ibus_lookup_table_get_number_of_candidates (table);
    guint page_size = ibus_lookup_table_get_page_size (table);
    guint cursor_pos = ibus_lookup_table_get_cursor_pos (table);
    guint pages = (page_size > 0) ? (n + page_size - 1) / page_size : 1;
    guint page = (page_size > 0) ? cursor_pos / page_size : 0;
    guint first = page * page_size;
    gboolean vertical =
            _force_vertical ||
            ibus_lookup_table_get_orientation (table) ==
                    IBUS_ORIENTATION_VERTICAL;
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
                [NSString stringWithFormat:@"%u.",
                        (guint)(i - first + 1)];
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

    /* The page number is only useful with multiple pages. */
    NSString *page_info = (pages > 1) ?
            [NSString stringWithFormat:@"%u/%u",
                    (guint)(page + 1), (guint)pages] : nil;

    [_candidate_window showCandidates:candidates
                          cursorIndex:(page_size > 0) ?
                                  (cursor_pos % page_size) : 0
                            auxiliary:_auxiliary
                              pageInfo:page_info
                              vertical:vertical
                          pageHandler:^(NSInteger delta) {
                              _page (delta);
                          }
                               around:_cursor_rect];
    (void) _preedit_visible;
}

static void
_update_lookup_table_cb (IBusPanelService *panel,
                         IBusLookupTable  *table,
                         gboolean          visible,
                         gpointer          user_data)
{
    if (visible && table != NULL) {
        guint n = ibus_lookup_table_get_number_of_candidates (table);
        IBusText *first = n > 0 ?
                ibus_lookup_table_get_candidate (table, 0) : NULL;
        g_debug ("lookup table: %u candidates, first: \"%s\"",
                 n, first ? first->text : "");
        g_clear_object (&_last_table);
        _last_table = (IBusLookupTable *) g_object_ref_sink (table);
        _show_lookup_table (table);
    }
    else {
        g_clear_object (&_last_table);
        _auxiliary = nil;
        _rerender ();
    }
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
    g_clear_object (&_last_table);
    _auxiliary = nil;
    _rerender ();
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
_rerender (void)
{
    if (_last_table != NULL)
        _show_lookup_table (_last_table);
    else if (_preedit_visible && _preedit != nil)
        [_candidate_window showPreedit:_preedit
                                 cursor:_preedit_cursor
                               vertical:FALSE
                                 around:_cursor_rect];
    else
        [_candidate_window hide];
}

static void
_update_preedit_text_cb (IBusPanelService *panel,
                         IBusText         *text,
                         guint             cursor_pos,
                         gboolean          visible,
                         gpointer          user_data)
{
    NSDictionary *attributes = @{
        NSFontAttributeName: [NSFont systemFontOfSize:14.0],
        NSForegroundColorAttributeName: [NSColor textColor],
    };
    _preedit = [[NSAttributedString alloc]
            initWithString:[NSString stringWithUTF8String:text->text]
              attributes:attributes];
    _preedit_cursor = cursor_pos;
    _preedit_visible = (visible != FALSE);
    g_debug ("panel preedit: \"%s\" cursor:%u visible:%d",
             text->text, cursor_pos, visible);
    _rerender ();
}

static void
_show_preedit_text_cb (IBusPanelService *panel,
                       gpointer          user_data)
{
    _preedit_visible = TRUE;
    _rerender ();
}

static void
_hide_preedit_text_cb (IBusPanelService *panel,
                       gpointer          user_data)
{
    _preedit_visible = FALSE;
    _preedit = nil;
    _rerender ();
}

static void
_update_auxiliary_text_cb (IBusPanelService *panel,
                           IBusText         *text,
                           gboolean          visible,
                           gpointer          user_data)
{
    if (!visible) {
        _auxiliary = nil;
        _rerender ();
        return;
    }
    NSDictionary *attributes = @{
        NSFontAttributeName: [NSFont systemFontOfSize:12.0],
        NSForegroundColorAttributeName: [NSColor secondaryLabelColor],
    };
    _auxiliary =
            [[NSAttributedString alloc]
                    initWithString:[NSString stringWithUTF8String:text->text]
                      attributes:attributes];
    /* The auxiliary text arrives after the lookup table of the same
     * key; render it together with the last table. */
    _rerender ();
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

    /* The daemon builds the panel proxy when the panel component
     * claims the component name on the ibus bus, like the engines
     * claim their component names. */
    if (!ibus_bus_request_name (_bus, IBUS_SERVICE_PANEL,
                                IBUS_BUS_NAME_FLAG_REPLACE_EXISTING)) {
        g_printerr ("ibus-ui-macospanel: cannot claim %s\n",
                    IBUS_SERVICE_PANEL);
        return;
    }

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
    g_signal_connect (_panel, "update-preedit-text",
                      G_CALLBACK (_update_preedit_text_cb), NULL);
    g_signal_connect (_panel, "show-preedit-text",
                      G_CALLBACK (_show_preedit_text_cb), NULL);
    g_signal_connect (_panel, "hide-preedit-text",
                      G_CALLBACK (_hide_preedit_text_cb), NULL);
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
    g_print ("ibus-ui-macospanel: connected to ibus-daemon\n");
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
    @autoreleasepool {
        ibus_init ();

        _force_vertical = (g_getenv ("IBUS_MACOSPANEL_VERTICAL") != NULL);

        _bus = ibus_bus_new_async_client ();
        g_signal_connect (_bus, "connected",
                          G_CALLBACK (_bus_connected_cb), NULL);
        g_signal_connect (_bus, "disconnected",
                          G_CALLBACK (_bus_disconnected_cb), NULL);

        _candidate_window = [[CandidateWindow alloc] init];

        CFRunLoopTimerContext context = { 0, NULL, NULL, NULL, NULL };
        CFRunLoopTimerRef timer = CFRunLoopTimerCreate (
                kCFAllocatorDefault, 0, 0.01, 0, 0,
                _glib_iteration, &context);
        CFRunLoopAddTimer (CFRunLoopGetMain (), timer, kCFRunLoopCommonModes);

        _app = [NSApplication sharedApplication];
        [_app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        if (ibus_bus_is_connected (_bus))
            _bus_connected_cb (_bus, NULL);
        [_app run];

        CFRunLoopRemoveTimer (CFRunLoopGetMain (), timer, kCFRunLoopCommonModes);
        CFRelease (timer);
    }
    return EXIT_SUCCESS;
}
