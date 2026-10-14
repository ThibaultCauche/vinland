#include "taskbar_controls.h"

#include <flutter/standard_method_codec.h>

#include "resource.h"

namespace {

constexpr UINT kPreviousId = 1;
constexpr UINT kPlayPauseId = 2;
constexpr UINT kNextId = 3;

}  // namespace

TaskbarControls::TaskbarControls(HWND window,
                                 flutter::BinaryMessenger* messenger)
    : window_(window),
      // Windows envoie ce message quand le bouton de la fenetre apparait
      // dans la barre des taches (et a chaque redemarrage d'Explorer) : les
      // boutons ne peuvent etre ajoutes qu'apres.
      taskbar_created_message_(RegisterWindowMessage(L"TaskbarButtonCreated")) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "vinland/taskbar",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        const auto* value = std::get_if<bool>(call.arguments());
        if (call.method_name() == "setPlaying" && value) {
          playing_ = *value;
        } else if (call.method_name() == "setEnabled" && value) {
          enabled_ = *value;
        } else {
          result->NotImplemented();
          return;
        }
        UpdateButtons();
        result->Success();
      });
}

std::optional<LRESULT> TaskbarControls::HandleMessage(UINT message,
                                                      WPARAM wparam,
                                                      LPARAM lparam) {
  if (message == taskbar_created_message_) {
    buttons_added_ = false;
    taskbar_.Reset();
    AddButtons();
    return 0;
  }
  if (message == WM_COMMAND && HIWORD(wparam) == THBN_CLICKED) {
    const char* button = nullptr;
    switch (LOWORD(wparam)) {
      case kPreviousId:
        button = "previous";
        break;
      case kPlayPauseId:
        button = "playPause";
        break;
      case kNextId:
        button = "next";
        break;
    }
    if (button) {
      channel_->InvokeMethod(
          "onButton",
          std::make_unique<flutter::EncodableValue>(std::string(button)));
      return 0;
    }
  }
  return std::nullopt;
}

HICON TaskbarControls::LoadButtonIcon(int resource_id) {
  // Taille d'une petite icone a l'echelle de l'ecran (16 px a 100 %).
  const int size = GetSystemMetrics(SM_CXSMICON);
  return static_cast<HICON>(LoadImage(GetModuleHandle(nullptr),
                                      MAKEINTRESOURCE(resource_id), IMAGE_ICON,
                                      size, size, LR_SHARED));
}

void TaskbarControls::AddButtons() {
  if (!taskbar_) {
    if (FAILED(CoCreateInstance(CLSID_TaskbarList, nullptr,
                                CLSCTX_INPROC_SERVER,
                                IID_PPV_ARGS(&taskbar_))) ||
        FAILED(taskbar_->HrInit())) {
      taskbar_.Reset();
      return;
    }
  }

  THUMBBUTTON buttons[3] = {};
  const UINT ids[3] = {kPreviousId, kPlayPauseId, kNextId};
  for (int i = 0; i < 3; i++) {
    buttons[i].dwMask = THB_ICON | THB_TOOLTIP | THB_FLAGS;
    buttons[i].iId = ids[i];
    buttons[i].dwFlags = enabled_ ? THBF_ENABLED : THBF_DISABLED;
  }
  buttons[0].hIcon = LoadButtonIcon(IDI_THUMB_PREVIOUS);
  wcscpy_s(buttons[0].szTip, L"Pr\u00e9c\u00e9dent");
  buttons[1].hIcon = LoadButtonIcon(playing_ ? IDI_THUMB_PAUSE : IDI_THUMB_PLAY);
  wcscpy_s(buttons[1].szTip, playing_ ? L"Pause" : L"Lecture");
  buttons[2].hIcon = LoadButtonIcon(IDI_THUMB_NEXT);
  wcscpy_s(buttons[2].szTip, L"Suivant");

  // La barre ne peut etre ajoutee qu'une fois par fenetre ; ensuite on ne
  // fait que la mettre a jour (UpdateButtons).
  buttons_added_ =
      SUCCEEDED(taskbar_->ThumbBarAddButtons(window_, 3, buttons));
}

void TaskbarControls::UpdateButtons() {
  if (!taskbar_) return;
  if (!buttons_added_) {
    AddButtons();
    return;
  }
  THUMBBUTTON buttons[3] = {};
  const UINT ids[3] = {kPreviousId, kPlayPauseId, kNextId};
  for (int i = 0; i < 3; i++) {
    buttons[i].dwMask = THB_FLAGS;
    buttons[i].iId = ids[i];
    buttons[i].dwFlags = enabled_ ? THBF_ENABLED : THBF_DISABLED;
  }
  buttons[1].dwMask |= THB_ICON | THB_TOOLTIP;
  buttons[1].hIcon = LoadButtonIcon(playing_ ? IDI_THUMB_PAUSE : IDI_THUMB_PLAY);
  wcscpy_s(buttons[1].szTip, playing_ ? L"Pause" : L"Lecture");
  taskbar_->ThumbBarUpdateButtons(window_, 3, buttons);
}
