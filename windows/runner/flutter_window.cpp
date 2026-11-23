#include "flutter_window.h"

#include <cstring>
#include <optional>
#include <vector>
#include <variant>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"

namespace {

constexpr UINT kTrayCallbackMessage = WM_APP + 101;
constexpr UINT kTrayIconId = 1;
constexpr int kHotKeyQuickSearchId = 1;
constexpr UINT kMenuShow = 1001;
constexpr UINT kMenuQuickSearch = 1002;
constexpr UINT kMenuLockVault = 1003;
constexpr UINT kMenuExit = 1004;

bool SetClipboardDwordFormat(const wchar_t* format_name, DWORD value) {
  UINT fmt = RegisterClipboardFormatW(format_name);
  if (fmt == 0) return false;
  HGLOBAL hMem = GlobalAlloc(GMEM_MOVEABLE, sizeof(DWORD));
  if (hMem == nullptr) return false;
  void* ptr = GlobalLock(hMem);
  if (ptr == nullptr) {
    GlobalFree(hMem);
    return false;
  }
  std::memcpy(ptr, &value, sizeof(DWORD));
  GlobalUnlock(hMem);
  if (SetClipboardData(fmt, hMem) == nullptr) {
    GlobalFree(hMem);
    return false;
  }
  return true;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  SetupNativeMethodChannel();
  SyncDesktopShell(tray_enabled_, hotkey_enabled_);

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  UnregisterGlobalHotkey();
  RemoveTrayIcon();

  if (method_channel_) {
    method_channel_->SetMethodCallHandler(nullptr);
    method_channel_.reset();
  }

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::SetupNativeMethodChannel() {
  method_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "com.multipad.multipad/native",
          &flutter::StandardMethodCodec::GetInstance());

  method_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        const auto& method = call.method_name();
        const auto* args =
            std::get_if<flutter::EncodableMap>(call.arguments());

        if (method == "copyConfidential") {
          std::string text;
          if (args != nullptr) {
            auto it = args->find(flutter::EncodableValue("text"));
            if (it != args->end()) {
              if (const auto* str = std::get_if<std::string>(&it->second)) {
                text = *str;
              }
            }
          }
          const bool copied = CopyConfidentialToClipboard(text);
          result->Success(flutter::EncodableValue(copied));
        } else if (method == "configureDesktopShell") {
          bool tray = true;
          bool hotkey = true;
          if (args != nullptr) {
            auto it_tray = args->find(flutter::EncodableValue("trayEnabled"));
            if (it_tray != args->end()) {
              if (const auto* b = std::get_if<bool>(&it_tray->second)) {
                tray = *b;
              }
            }
            auto it_hk =
                args->find(flutter::EncodableValue("globalHotkeyEnabled"));
            if (it_hk != args->end()) {
              if (const auto* b = std::get_if<bool>(&it_hk->second)) {
                hotkey = *b;
              }
            }
          }
          SyncDesktopShell(tray, hotkey);
          result->Success(flutter::EncodableValue(true));
        } else if (method == "bringWindowToFront") {
          BringWindowToFront();
          result->Success(flutter::EncodableValue(true));
        } else if (method == "windowStartDragging") {
          HWND hwnd = GetHandle();
          if (hwnd != nullptr) {
            ::ReleaseCapture();
            ::SendMessageW(hwnd, WM_NCLBUTTONDOWN, HTCAPTION, 0);
          }
          result->Success(flutter::EncodableValue(true));
        } else if (method == "windowMinimize") {
          HWND hwnd = GetHandle();
          if (hwnd != nullptr) {
            ::ShowWindow(hwnd, SW_MINIMIZE);
          }
          result->Success(flutter::EncodableValue(true));
        } else if (method == "windowMaximize") {
          HWND hwnd = GetHandle();
          if (hwnd != nullptr) {
            if (::IsZoomed(hwnd)) {
              ::ShowWindow(hwnd, SW_RESTORE);
            } else {
              ::ShowWindow(hwnd, SW_MAXIMIZE);
            }
          }
          result->Success(flutter::EncodableValue(true));
        } else if (method == "windowClose") {
          HWND hwnd = GetHandle();
          if (hwnd != nullptr) {
            ::PostMessageW(hwnd, WM_CLOSE, 0, 0);
          }
          result->Success(flutter::EncodableValue(true));
        } else if (method == "isWindowMaximized") {
          HWND hwnd = GetHandle();
          bool is_max = (hwnd != nullptr) && ::IsZoomed(hwnd);
          result->Success(flutter::EncodableValue(is_max));
        } else if (method == "setFlagSecure" || method == "setMulticastLock") {
          result->Success(flutter::EncodableValue(true));
        } else {
          result->NotImplemented();
        }
      });
}

bool FlutterWindow::CopyConfidentialToClipboard(const std::string& utf8_text) {
  int wide_len = MultiByteToWideChar(
      CP_UTF8, 0, utf8_text.data(), static_cast<int>(utf8_text.size()), nullptr, 0);
  std::vector<wchar_t> wide_buf(static_cast<size_t>(wide_len) + 1, L'\0');
  if (wide_len > 0) {
    MultiByteToWideChar(CP_UTF8, 0, utf8_text.data(),
                        static_cast<int>(utf8_text.size()), wide_buf.data(),
                        wide_len);
  }

  HWND hwnd = GetHandle();
  if (!OpenClipboard(hwnd)) {
    return false;
  }

  EmptyClipboard();

  bool wrote_text = false;
  const size_t byte_size = wide_buf.size() * sizeof(wchar_t);
  HGLOBAL hMem = GlobalAlloc(GMEM_MOVEABLE, byte_size);
  if (hMem != nullptr) {
    void* dst = GlobalLock(hMem);
    if (dst != nullptr) {
      std::memcpy(dst, wide_buf.data(), byte_size);
      GlobalUnlock(hMem);
      if (SetClipboardData(CF_UNICODETEXT, hMem) != nullptr) {
        wrote_text = true;
      } else {
        GlobalFree(hMem);
      }
    } else {
      GlobalFree(hMem);
    }
  }

  // Exclude copied secret from Windows 10/11 Clipboard History & Cloud Sync
  if (wrote_text) {
    SetClipboardDwordFormat(L"ExcludeClipboardContentFromMonitorProcessing", 1);
    SetClipboardDwordFormat(L"CanIncludeInClipboardHistory", 0);
    SetClipboardDwordFormat(L"CanUploadToCloudClipboard", 0);
  }

  CloseClipboard();
  return wrote_text;
}

void FlutterWindow::SyncDesktopShell(bool tray_enabled, bool hotkey_enabled) {
  tray_enabled_ = tray_enabled;
  hotkey_enabled_ = hotkey_enabled;
  if (tray_enabled_) {
    EnsureTrayIcon();
  } else {
    RemoveTrayIcon();
  }
  SyncGlobalHotkey();
}

void FlutterWindow::EnsureTrayIcon() {
  if (tray_added_) return;
  HWND hwnd = GetHandle();
  if (hwnd == nullptr) return;

  std::memset(&tray_icon_, 0, sizeof(tray_icon_));
  tray_icon_.cbSize = sizeof(NOTIFYICONDATAW);
  tray_icon_.hWnd = hwnd;
  tray_icon_.uID = kTrayIconId;
  tray_icon_.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
  tray_icon_.uCallbackMessage = kTrayCallbackMessage;

  HICON icon = LoadIconW(GetModuleHandleW(nullptr),
                         MAKEINTRESOURCEW(IDI_APP_ICON));
  if (icon == nullptr) {
    icon = LoadIconW(nullptr, IDI_APPLICATION);
  }
  tray_icon_.hIcon = icon;
  wcscpy_s(tray_icon_.szTip, L"MultiPad");

  if (Shell_NotifyIconW(NIM_ADD, &tray_icon_)) {
    tray_added_ = true;
  }
}

void FlutterWindow::RemoveTrayIcon() {
  if (!tray_added_) return;
  Shell_NotifyIconW(NIM_DELETE, &tray_icon_);
  tray_added_ = false;
}

void FlutterWindow::SyncGlobalHotkey() {
  HWND hwnd = GetHandle();
  if (hwnd == nullptr) return;

  if (!hotkey_enabled_) {
    UnregisterGlobalHotkey();
    return;
  }

  if (hotkey_registered_) return;
  if (RegisterHotKey(hwnd, kHotKeyQuickSearchId,
                     MOD_CONTROL | MOD_SHIFT | MOD_NOREPEAT, VK_SPACE)) {
    hotkey_registered_ = true;
    hotkey_hwnd_ = hwnd;
  }
}

void FlutterWindow::UnregisterGlobalHotkey() {
  if (!hotkey_registered_) return;
  HWND hwnd = hotkey_hwnd_ != nullptr ? hotkey_hwnd_ : GetHandle();
  if (hwnd != nullptr) {
    UnregisterHotKey(hwnd, kHotKeyQuickSearchId);
  }
  hotkey_registered_ = false;
  hotkey_hwnd_ = nullptr;
}

void FlutterWindow::BringWindowToFront() {
  HWND hwnd = GetHandle();
  if (hwnd == nullptr) return;
  if (IsIconic(hwnd)) {
    ShowWindow(hwnd, SW_RESTORE);
  } else {
    ShowWindow(hwnd, SW_SHOW);
  }
  SetForegroundWindow(hwnd);
}

void FlutterWindow::ShowTrayContextMenu(HWND window) {
  POINT pt{};
  GetCursorPos(&pt);

  HMENU menu = CreatePopupMenu();
  if (menu == nullptr) return;

  AppendMenuW(menu, MF_STRING, kMenuShow, L"MultiPad'i G\u00f6ster");
  AppendMenuW(menu, MF_STRING, kMenuQuickSearch,
              L"H\u0131zl\u0131 Arama (Ctrl+Shift+Space)");
  AppendMenuW(menu, MF_STRING, kMenuLockVault, L"Kasay\u0131 Kilitle");
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kMenuExit, L"\u00c7\u0131k\u0131\u015f");

  SetForegroundWindow(window);
  UINT cmd = static_cast<UINT>(TrackPopupMenu(
      menu, TPM_RETURNCMD | TPM_NONOTIFY | TPM_RIGHTBUTTON, pt.x, pt.y, 0,
      window, nullptr));
  PostMessageW(window, WM_NULL, 0, 0);
  DestroyMenu(menu);

  switch (cmd) {
    case kMenuShow:
      BringWindowToFront();
      break;
    case kMenuQuickSearch:
      BringWindowToFront();
      if (method_channel_) {
        method_channel_->InvokeMethod(
            "onQuickSearchRequested",
            std::make_unique<flutter::EncodableValue>());
      }
      break;
    case kMenuLockVault:
      if (method_channel_) {
        method_channel_->InvokeMethod(
            "onLockVaultRequested",
            std::make_unique<flutter::EncodableValue>());
      }
      break;
    case kMenuExit:
      explicit_quit_ = true;
      PostMessageW(window, WM_CLOSE, 0, 0);
      break;
    default:
      break;
  }
}

LRESULT FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                                      WPARAM const wparam,
                                      LPARAM const lparam) noexcept {
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_ENDSESSION:
      if (wparam != FALSE) {
        explicit_quit_ = true;
        RemoveTrayIcon();
        UnregisterGlobalHotkey();
      }
      break;
    case WM_CLOSE:
      if (tray_enabled_ && !explicit_quit_) {
        ShowWindow(hwnd, SW_HIDE);
        return 0;
      }
      break;

    case WM_HOTKEY:
      if (static_cast<int>(wparam) == kHotKeyQuickSearchId) {
        BringWindowToFront();
        if (method_channel_) {
          method_channel_->InvokeMethod(
              "onQuickSearchRequested",
              std::make_unique<flutter::EncodableValue>());
        }
        return 0;
      }
      break;

    case kTrayCallbackMessage: {
      UINT tray_event = LOWORD(lparam);
      if (tray_event == WM_LBUTTONDBLCLK) {
        BringWindowToFront();
      } else if (tray_event == WM_RBUTTONUP || tray_event == WM_CONTEXTMENU) {
        ShowTrayContextMenu(hwnd);
      }
      return 0;
    }

    case WM_FONTCHANGE:
      if (flutter_controller_ && flutter_controller_->engine()) {
        flutter_controller_->engine()->ReloadSystemFonts();
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
