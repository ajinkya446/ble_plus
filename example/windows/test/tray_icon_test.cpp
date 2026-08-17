// Unit tests for the tray icon / background of the Windows runner.
// They cover the behavior implemented in
// example/windows/runner/win32_window.cpp:
//   1. Closing the window (WM_CLOSE) hides it to the tray without destroying
//      the process.
//   2. Double-clicking the tray (message with WM_LBUTTONDBLCLK) restores the
//      window.
//   3. On exit (WM_DESTROY) the tray icon is removed and the window is
//      destroyed.
//
// A minimal Win32Window subclass is used (without the Flutter engine) and the
// messages are sent with SendMessage, so neither a message pump nor an
// interactive session is required.

#include <windows.h>

#include <gtest/gtest.h>

#include "win32_window.h"

namespace {

// Minimal Win32Window subclass for the test (does not initialize Flutter).
class TestWindow : public Win32Window {
 public:
  bool created_ = false;

 protected:
  bool OnCreate() override {
    created_ = true;
    return true;
  }
};

// Creates and shows a test window, returning its HWND.
// Note: Win32Window::Show() returns the result of ShowWindow, which is FALSE
// when the PREVIOUS state was hidden (not an error); that is why
// IsWindowVisible is checked instead of the return value. With `background` =
// true, background mode is enabled (what enableBackground → runner does).
HWND CreateAndShow(TestWindow* window, bool background = true) {
  EXPECT_TRUE(window->Create(L"tray_test", {0, 0}, {200, 200}));
  if (background) {
    window->SetBackgroundMode(true);
  }
  window->Show();
  HWND hwnd = window->GetHandle();
  EXPECT_NE(hwnd, nullptr);
  EXPECT_TRUE(IsWindowVisible(hwnd));
  return hwnd;
}

// 1) Close (WM_CLOSE) → hide to tray: the window stays alive (the process
// keeps running) but invisible, and the tray icon is added.
TEST(TrayIconTest, CloseHidesToTrayAndKeepsWindowAlive) {
  TestWindow window;
  HWND hwnd = CreateAndShow(&window);
  ASSERT_TRUE(IsWindowVisible(hwnd));

  SendMessage(hwnd, WM_CLOSE, 0, 0);

  EXPECT_TRUE(IsWindow(hwnd)) << "the window must not be destroyed on close";
  EXPECT_FALSE(IsWindowVisible(hwnd)) << "the window must be hidden";
  EXPECT_TRUE(window.IsTrayIconAdded()) << "the tray icon must be added";
}

// 2) Double-click on the tray → restore the window (visible again).
TEST(TrayIconTest, DoubleClickRestoresWindow) {
  TestWindow window;
  HWND hwnd = CreateAndShow(&window);

  SendMessage(hwnd, WM_CLOSE, 0, 0);
  ASSERT_FALSE(IsWindowVisible(hwnd));

  SendMessage(hwnd, Win32Window::kTrayCallbackMessage, 0,
              MAKELPARAM(WM_LBUTTONDBLCLK, 0));

  EXPECT_TRUE(IsWindow(hwnd)) << "the window must still exist";
  EXPECT_TRUE(IsWindowVisible(hwnd)) << "double-click must restore the window";
}

// 3) Exit (DestroyWindow → WM_DESTROY) → remove the tray icon and destroy the
// window. DestroyWindow is used (as QuitFromTray does) because a manually sent
// WM_DESTROY does not destroy the window by itself.
TEST(TrayIconTest, DestroyRemovesTrayIcon) {
  TestWindow window;
  HWND hwnd = CreateAndShow(&window);

  SendMessage(hwnd, WM_CLOSE, 0, 0);
  ASSERT_TRUE(window.IsTrayIconAdded());

  DestroyWindow(hwnd);

  EXPECT_FALSE(window.IsTrayIconAdded()) << "the icon must be removed on exit";
  EXPECT_FALSE(IsWindow(hwnd)) << "the window must be destroyed on exit";
}

// 4) Without background mode (default), closing (WM_CLOSE) ends the app: the
// window is destroyed (the WM_CLOSE default) and no tray icon is added. This
// validates the link with enableBackground/disableBackground: background is
// only active when the app enables it.
TEST(TrayIconTest, CloseWithoutBackgroundDestroysWindow) {
  TestWindow window;
  HWND hwnd = CreateAndShow(&window, /*background=*/false);

  SendMessage(hwnd, WM_CLOSE, 0, 0);

  EXPECT_FALSE(window.IsTrayIconAdded()) << "without background there must be no tray";
  EXPECT_FALSE(IsWindow(hwnd)) << "without background close must destroy the window";
}

// 5) Disabling background (disableBackground) removes the tray icon if it was
// added and stops hiding on close.
TEST(TrayIconTest, DisableBackgroundRemovesTrayAndClosesOnClose) {
  TestWindow window;
  HWND hwnd = CreateAndShow(&window, /*background=*/true);
  SendMessage(hwnd, WM_CLOSE, 0, 0);
  ASSERT_TRUE(window.IsTrayIconAdded());

  window.SetBackgroundMode(false);
  EXPECT_FALSE(window.IsTrayIconAdded()) << "disabling must remove the icon";

  // The window is hidden by the previous WM_CLOSE; now a new close destroys
  // it (background mode is gone).
  SendMessage(hwnd, WM_CLOSE, 0, 0);
  EXPECT_FALSE(IsWindow(hwnd)) << "without background close destroys the window";
}

}  // namespace
