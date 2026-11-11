#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <string>

#include "win32_window.h"

#include <shellapi.h>

// A window hosting the MultiPad Flutter view plus Win32 tray, hotkey & clipboard protection.
class FlutterWindow : public Win32Window {
 public:
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  void SetupNativeMethodChannel();
  bool CopyConfidentialToClipboard(const std::string& utf8_text);
  void SyncDesktopShell(bool tray_enabled, bool hotkey_enabled);
  void EnsureTrayIcon();
  void RemoveTrayIcon();
  void SyncGlobalHotkey();
  void UnregisterGlobalHotkey();
  void BringWindowToFront();
  void ShowTrayContextMenu(HWND window);

  flutter::DartProject project_;
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      method_channel_;

  bool tray_enabled_ = true;
  bool hotkey_enabled_ = true;
  bool tray_added_ = false;
  bool hotkey_registered_ = false;
  bool explicit_quit_ = false;
  HWND hotkey_hwnd_ = nullptr;
  NOTIFYICONDATAW tray_icon_{};
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
