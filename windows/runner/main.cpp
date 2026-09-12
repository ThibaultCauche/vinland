#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

// Sur un portable a cartes graphiques hybrides (Intel integree + NVIDIA/AMD
// dediee), Windows fait tourner par defaut une appli desktop non plein-ecran
// sur le GPU integre pour economiser la batterie -- meme quand une carte
// dediee est disponible et inactive. Mesure sur cette machine (Intel UHD
// Graphics vs GeForce GTX 1650, via flutter drive --profile +
// integration_test/scroll_perf_test.dart) : ~51ms/frame de rasterisation en
// moyenne sur l'iGPU contre ~9ms sur la dediee -- facteur ~6x, largement le
// plus gros goulot d'etranglement identifie sur le scroll de la home. Ces
// deux symboles exportes sont la convention standard (Unity, Unreal, etc.)
// que les pilotes NVIDIA Optimus / AMD PowerXpress detectent pour choisir le
// GPU dedie automatiquement, sans configuration manuelle de l'utilisateur
// dans les parametres Windows.
extern "C" {
__declspec(dllexport) DWORD NvOptimusEnablement = 0x00000001;
__declspec(dllexport) DWORD AmdPowerXpressRequestHighPerformance = 0x00000001;
}

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

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"Vinland", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
