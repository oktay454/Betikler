#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>
#include <sys/wait.h>

// Aldığı tüm parametreleri, program ve parametreleri olarak çalıştırır.
// Aşağıdaki komut ile derleyebilirsiniz. Debian 12'de denendi.
// gcc tinywm.c -o tinywm -lX11

int main(int argc, char *argv[]) {
    if (argc < 2) {
        fprintf(stderr, "Kullanım: %s <uygulama> [parametreler]\n", argv[0]);
        return 1;
    }

    // Çocuk süreçte uygulamayı çalıştır
    pid_t pid = fork();
    if (pid == 0) {
        // argv[1] -> çalışacak uygulama,
        // argv[2..] -> uygulamaya geçilecek parametreler
        execvp(argv[1], &argv[1]);
        perror("execvp başarısız");
        exit(EXIT_FAILURE);
    } else if (pid < 0) {
        perror("fork başarısız");
        exit(EXIT_FAILURE);
    }

    // Ebeveyn süreç (TinyWM)
    Display *display = XOpenDisplay(NULL);
    if (!display) {
        fprintf(stderr, "TinyWM: X11 display açılamadı!\n");
        return 1;
    }

    // Tek ekran, root penceresi
    int screen = DefaultScreen(display);
    Window root = RootWindow(display, screen);

    // Root penceresini olaylar için dinle (redirect)
    XSelectInput(display, root, SubstructureRedirectMask | SubstructureNotifyMask);

    Window focused_window = None;
    XEvent event;

    while (1) {
        // Yeni bir olayı bekle
        XNextEvent(display, &event);

        switch (event.type) {
            case MapRequest:
                // Yeni bir pencere talebi
                XMapWindow(display, event.xmaprequest.window);

                // Tam ekran yap
                XMoveResizeWindow(
                    display,
                    event.xmaprequest.window,
                    0, 0,
                    DisplayWidth(display, screen),
                    DisplayHeight(display, screen)
                );

                // Odak ver
                XSetInputFocus(
                    display,
                    event.xmaprequest.window,
                    RevertToPointerRoot,
                    CurrentTime
                );
                focused_window = event.xmaprequest.window;
                break;

            case KeyPress:
            case KeyRelease:
            case ButtonPress:
            case ButtonRelease:
                // Tüm tuş/fare olaylarını odaklı pencereye yönlendir
                if (focused_window != None) {
                    XSendEvent(display, focused_window, True, NoEventMask, &event);
                }
                break;

            default:
                // Diğer olayları pas geç
                break;
        }

        // Çocuk süreç (uygulama) bitti mi kontrol edelim
        int status;
        pid_t w = waitpid(pid, &status, WNOHANG);
        if (w == pid) {
            // Uygulama kapanmışsa, WM de kapansın
            break;
        }
    }

    XCloseDisplay(display);
    return 0;
}

