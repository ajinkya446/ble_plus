#ifndef RUNNER_WIN32_WINDOW_H_
#define RUNNER_WIN32_WINDOW_H_

#include <windows.h>

#include <functional>
#include <memory>
#include <string>

// A class abstraction for a high DPI-aware Win32 Window. Intended to be
// inherited from by classes that wish to specialize with custom
// rendering and input handling
class Win32Window {
 public:
  struct Point {
    unsigned int x;
    unsigned int y;
    Point(unsigned int x, unsigned int y) : x(x), y(y) {}
  };

  struct Size {
    unsigned int width;
    unsigned int height;
    Size(unsigned int width, unsigned int height)
        : width(width), height(height) {}
  };

  Win32Window();
  virtual ~Win32Window();

  // Creates a win32 window with |title| that is positioned and sized using
  // |origin| and |size|. New windows are created on the default monitor. Window
  // sizes are specified to the OS in physical pixels, hence to ensure a
  // consistent size this function will scale the inputted width and height as
  // as appropriate for the default monitor. The window is invisible until
  // |Show| is called. Returns true if the window was created successfully.
  bool Create(const std::wstring& title, const Point& origin, const Size& size);

  // Show the current window. Returns true if the window was successfully shown.
  bool Show();

  // Release OS resources associated with window.
  void Destroy();

  // Inserts |content| into the window tree.
  void SetChildContent(HWND content);

  // Returns the backing Window handle to enable clients to set icon and other
  // window properties. Returns nullptr if the window has been destroyed.
  HWND GetHandle();

  // If true, closing this window will quit the application.
  void SetQuitOnClose(bool quit_on_close);

  // Returns whether the tray icon is currently added (used by the automated
  // tray tests; see example/windows/test/tray_icon_test.cpp).
  bool IsTrayIconAdded() const { return tray_icon_added_; }

  // Custom message that the tray icon (Shell_NotifyIcon) sends to the window
  // proc. `WM_APP + 1` is reserved for application messages. Public so the
  // automated test can send it (SendMessage).
  static constexpr UINT kTrayCallbackMessage = WM_APP + 1;

  // Enables/disables the runner background mode: when active, closing the
  // window (WM_CLOSE) hides it to the tray instead of terminating the process
  // (BLE keeps running). When disabled, the tray icon is removed if present and
  // closing terminates the process again. Invoked by the channel
  // "ble_plus/runner_background" (see FlutterWindow::OnCreate).
  void SetBackgroundMode(bool enabled);

  // Return a RECT representing the bounds of the current client area.
  RECT GetClientArea();

 protected:
  // Processes and route salient window messages for mouse handling,
  // size change and DPI. Delegates handling of these to member overloads that
  // inheriting classes can handle.
  virtual LRESULT MessageHandler(HWND window,
                                 UINT const message,
                                 WPARAM const wparam,
                                 LPARAM const lparam) noexcept;

  // Called when CreateAndShow is called, allowing subclass window-related
  // setup. Subclasses should return false if setup fails.
  virtual bool OnCreate();

  // Called when Destroy is called.
  virtual void OnDestroy();

 private:
  friend class WindowClassRegistrar;

  // OS callback called by message pump. Handles the WM_NCCREATE message which
  // is passed when the non-client area is being created and enables automatic
  // non-client DPI scaling so that the non-client area automatically
  // responds to changes in DPI. All other messages are handled by
  // MessageHandler.
  static LRESULT CALLBACK WndProc(HWND const window,
                                  UINT const message,
                                  WPARAM const wparam,
                                  LPARAM const lparam) noexcept;

  // Retrieves a class instance pointer for |window|
  static Win32Window* GetThisFromHandle(HWND const window) noexcept;

  // Update the window frame's theme to match the system theme.
  static void UpdateTheme(HWND const window);

  // ── Tray icon / background ────────────────────────────────────────────────
  // Hides the window to the tray instead of closing it: the process (and the
  // BLE) keep running in background. Called from WM_CLOSE.
  void HideToTray(HWND window);

  // Shows the tray context menu (Restore / Exit).
  void ShowTrayMenu(HWND window);

  // Removes the tray icon.
  void RemoveTrayIcon(HWND window);

  // Actually closes the app from the tray menu.
  void QuitFromTray(HWND window);

  bool quit_on_close_ = false;

  // window handle for top level window.
  HWND window_handle_ = nullptr;

  // window handle for hosted content.
  HWND child_content_ = nullptr;

  // Whether the tray icon is added (so it is not duplicated on hot restart).
  bool tray_icon_added_ = false;

  // Whether background mode is active (hide to tray on close). Disabled by
  // default: only `enableBackground` (runner channel) activates it, like on
  // the rest of the plugin's platforms.
  bool background_mode_ = false;
};

#endif  // RUNNER_WIN32_WINDOW_H_
