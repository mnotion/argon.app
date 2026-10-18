#define WIN32_LEAN_AND_MEAN
#include <windows.h>

// Deliberately inert bootstrap target used only to carry a versioned updater
// executable. Update application behaviour belongs to a future updater release.
int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int)
{
    return 0;
}
