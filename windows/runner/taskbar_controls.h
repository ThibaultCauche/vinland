#ifndef RUNNER_TASKBAR_CONTROLS_H_
#define RUNNER_TASKBAR_CONTROLS_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <shobjidl.h>
#include <windows.h>
#include <wrl/client.h>

#include <memory>
#include <optional>

// Boutons precedent / lecture-pause / suivant dans l'apercu de la fenetre au
// survol de son icone dans la barre des taches (ITaskbarList3 « thumbnail
// toolbar », comme Spotify). Pilotes depuis Dart par le channel
// "vinland/taskbar" (lib/desktop/taskbar_controls.dart) :
//  - Dart -> natif : setPlaying(bool), setEnabled(bool)
//  - natif -> Dart : onButton("previous" | "playPause" | "next")
class TaskbarControls {
 public:
  TaskbarControls(HWND window, flutter::BinaryMessenger* messenger);

  // A appeler depuis la procedure de la fenetre principale, avant les
  // plugins : renvoie une valeur si le message a ete traite ici.
  std::optional<LRESULT> HandleMessage(UINT message, WPARAM wparam,
                                       LPARAM lparam);

 private:
  void AddButtons();
  void UpdateButtons();
  HICON LoadButtonIcon(int resource_id);

  HWND window_;
  UINT taskbar_created_message_;
  Microsoft::WRL::ComPtr<ITaskbarList3> taskbar_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  bool buttons_added_ = false;
  bool playing_ = false;
  bool enabled_ = false;
};

#endif  // RUNNER_TASKBAR_CONTROLS_H_
