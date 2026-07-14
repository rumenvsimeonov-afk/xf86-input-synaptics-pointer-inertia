/*
 * Listen for Escape and request pointer-inertia drag-lock cancellation.
 *
 * This helper intentionally runs outside the input driver. X.Org input
 * drivers do not receive each other's event streams, so keyboard-triggered
 * touchpad cancellation is cleaner as a small X session process.
 */

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include <X11/Xatom.h>
#include <X11/XKBlib.h>
#include <X11/Xlib.h>
#include <X11/keysym.h>
#include <X11/extensions/XInput2.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "synaptics-properties.h"

static const char *device_name;
static int verbose;

static void
usage(int status)
{
    fprintf(stderr,
            "Usage: pointer-inertia-esc-cancel [-n device-name] [-v]\n"
            "  -n  Use the named touchpad instead of auto-detecting one\n"
            "  -v  Print a line each time Escape requests cancellation\n");
    exit(status);
}

static int
device_has_property(Display *display, int deviceid, Atom property)
{
    Atom type;
    int format;
    unsigned long nitems;
    unsigned long bytes_after;
    unsigned char *data = NULL;
    int rc;

    rc = XIGetProperty(display, deviceid, property, 0, 1, False,
                       AnyPropertyType, &type, &format, &nitems,
                       &bytes_after, &data);
    if (data)
        XFree(data);

    return rc == Success && type != None;
}

static int
find_touchpad(Display *display, Atom cancel_property)
{
    XIDeviceInfo *devices;
    int ndevices;
    int deviceid = -1;

    devices = XIQueryDevice(display, XIAllDevices, &ndevices);
    if (!devices)
        return -1;

    for (int i = 0; i < ndevices; i++) {
        if (device_name && strcmp(devices[i].name, device_name) != 0)
            continue;
        if (!device_has_property(display, devices[i].deviceid,
                                 cancel_property))
            continue;

        deviceid = devices[i].deviceid;
        if (verbose)
            fprintf(stderr, "Using touchpad: %s (id %d)\n",
                    devices[i].name, deviceid);
        break;
    }

    XIFreeDeviceInfo(devices);
    return deviceid;
}

static void
trigger_cancel(Display *display, int deviceid, Atom cancel_property)
{
    unsigned char value;

    value = 0;
    XIChangeProperty(display, deviceid, cancel_property, XA_INTEGER, 8,
                     PropModeReplace, &value, 1);
    value = 1;
    XIChangeProperty(display, deviceid, cancel_property, XA_INTEGER, 8,
                     PropModeReplace, &value, 1);
    value = 0;
    XIChangeProperty(display, deviceid, cancel_property, XA_INTEGER, 8,
                     PropModeReplace, &value, 1);
    XFlush(display);

    if (verbose)
        fprintf(stderr, "Escape requested drag-lock cancellation\n");
}

static void
select_raw_escape_events(Display *display)
{
    unsigned char mask[XIMaskLen(XI_RawKeyPress)] = { 0 };
    XIEventMask event_mask;
    int major = 2;
    int minor = 0;

    if (XIQueryVersion(display, &major, &minor) != Success) {
        fprintf(stderr, "XInput2 is not available.\n");
        exit(1);
    }

    XISetMask(mask, XI_RawKeyPress);
    event_mask.deviceid = XIAllMasterDevices;
    event_mask.mask_len = sizeof(mask);
    event_mask.mask = mask;

    XISelectEvents(display, DefaultRootWindow(display), &event_mask, 1);
    XFlush(display);
}

int
main(int argc, char **argv)
{
    Display *display;
    Atom cancel_property;
    int xi_opcode;
    int xi_event;
    int xi_error;
    int deviceid;
    int opt;

    while ((opt = getopt(argc, argv, "hn:v")) != -1) {
        switch (opt) {
        case 'n':
            device_name = optarg;
            break;
        case 'v':
            verbose = 1;
            break;
        case 'h':
            usage(0);
            break;
        default:
            usage(2);
            break;
        }
    }

    display = XOpenDisplay(NULL);
    if (!display) {
        fprintf(stderr, "Cannot open X display.\n");
        return 1;
    }

    if (!XQueryExtension(display, "XInputExtension", &xi_opcode, &xi_event,
                         &xi_error)) {
        fprintf(stderr, "XInput extension is not available.\n");
        return 1;
    }

    cancel_property =
        XInternAtom(display, SYNAPTICS_PROP_POINTER_INERTIA_DRAG_LOCK_CANCEL,
                    True);
    if (cancel_property == None) {
        fprintf(stderr, "Pointer inertia drag-lock cancel property is absent.\n");
        return 1;
    }

    deviceid = find_touchpad(display, cancel_property);
    if (deviceid < 0) {
        fprintf(stderr, "No touchpad with pointer inertia cancel property found.\n");
        return 1;
    }

    select_raw_escape_events(display);

    for (;;) {
        XEvent event;

        XNextEvent(display, &event);
        if (event.xcookie.type != GenericEvent ||
            event.xcookie.extension != xi_opcode)
            continue;

        if (!XGetEventData(display, &event.xcookie))
            continue;

        if (event.xcookie.evtype == XI_RawKeyPress) {
            XIRawEvent *raw = event.xcookie.data;
            KeySym keysym = XkbKeycodeToKeysym(display, raw->detail, 0, 0);

            if (keysym == XK_Escape)
                trigger_cancel(display, deviceid, cancel_property);
        }

        XFreeEventData(display, &event.xcookie);
    }

    return 0;
}
