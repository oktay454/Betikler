#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>

// Aşağıdaki komut ile derlenebilir. Debian 12'de denendi.
// gcc -o fullscreen_tinywm fullscreen_tinywm.c -lX11

int main() {
    Display *display;
    Window root, focused_window = None;
    XEvent event;

    // X11 bağlantısını aç
    display = XOpenDisplay(NULL);
    if (!display) {
        fprintf(stderr, "TinyWM: X11 display açılamadı!\n");
        exit(EXIT_FAILURE);
    }

    root = DefaultRootWindow(display);

    // Root penceresini olaylar için dinle
    XSelectInput(display, root, SubstructureRedirectMask | SubstructureNotifyMask);

    // Sonsuz döngü: Pencereleri yöneten ana olay döngüsü
    while (1) {
        XNextEvent(display, &event);

        if (event.type == MapRequest) {
            // Yeni bir pencere talebi geldiğinde
            XMapWindow(display, event.xmaprequest.window);

            // Pencereyi tam ekran yap
            XMoveResizeWindow(display, event.xmaprequest.window, 0, 0,
                              DisplayWidth(display, DefaultScreen(display)),
                              DisplayHeight(display, DefaultScreen(display)));

            // Odağı pencereye ver
            XSetInputFocus(display, event.xmaprequest.window, RevertToPointerRoot, CurrentTime);
            focused_window = event.xmaprequest.window;
        } else if (event.type == KeyPress || event.type == KeyRelease || event.type == ButtonPress || event.type == ButtonRelease) {
            // Tüm tuş ve fare olaylarını doğrudan odaklanmış pencereye ilet
            if (focused_window != None) {
                XSendEvent(display, focused_window, True, NoEventMask, &event);
            }
        }
    }

    XCloseDisplay(display);
    return 0;
}

