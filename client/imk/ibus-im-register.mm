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

/*
 * Register the IBusIM.app input method with Text Input Services of
 * the current user session.  The modern macOS releases do not rescan
 * the Input Methods folders automatically, so the installers run
 * this tool with TISRegisterInputSource() and enable the registered
 * input sources with TISEnableInputSource().
 *
 * Usage: ibus-im-register <path-to-app.app> [bundle-identifier]
 */

#import <Carbon/Carbon.h>
#import <Foundation/Foundation.h>

int
main (int    argc,
      char **argv)
{
    @autoreleasepool {
        if (argc < 2) {
            printf ("Usage: %s <path-to-IBusIM.app>\n", argv[0]);
            return EXIT_FAILURE;
        }

        NSURL *url = [NSURL fileURLWithPath:@(argv[1])];
        NSString *bundle_id = argc > 2 ?
                @(argv[2]) : @"org.freedesktop.IBus.IM";
        OSStatus status = TISRegisterInputSource ((__bridge CFURLRef) url);
        if (status != noErr) {
            printf ("TISRegisterInputSource failed: %d\n", (int) status);
            return EXIT_FAILURE;
        }

        /* Enable the registered input sources of the bundle: the
         * parent source has the bundle identifier as the input
         * source ID, and the modes are registered below it. */
        NSDictionary *conditions =
                @{ (__bridge NSString *) kTISPropertyBundleID:
                           bundle_id };
        CFArrayRef sources = TISCreateInputSourceList (
                (__bridge CFDictionaryRef) conditions, TRUE);
        int enabled = 0;
        for (CFIndex i = 0; sources && i < CFArrayGetCount (sources); i++) {
            TISInputSourceRef source =
                    (TISInputSourceRef) CFArrayGetValueAtIndex (sources, i);
            status = TISEnableInputSource (source);
            if (status == noErr)
                enabled++;
        }
        if (sources)
            CFRelease (sources);
        printf ("%d input source(s) enabled\n", enabled);
        return enabled > 0 ? EXIT_SUCCESS : EXIT_FAILURE;
    }
}
