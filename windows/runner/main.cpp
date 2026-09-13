#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments = GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(620, 800);
  if (!window.Create(L"pcalc express", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  // Center the DPI-scaled native window without a window-management plugin.
  const HWND handle = window.GetHandle();
  MONITORINFO monitor_info{};
  monitor_info.cbSize = sizeof(monitor_info);
  RECT bounds{};
  if (GetMonitorInfo(MonitorFromWindow(handle, MONITOR_DEFAULTTONEAREST),
                     &monitor_info) &&
      GetWindowRect(handle, &bounds)) {
    const RECT &work = monitor_info.rcWork;
    const int width = bounds.right - bounds.left;
    const int height = bounds.bottom - bounds.top;
    SetWindowPos(handle, nullptr,
                 work.left + (work.right - work.left - width) / 2,
                 work.top + (work.bottom - work.top - height) / 2, 0, 0,
                 SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
  }

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
