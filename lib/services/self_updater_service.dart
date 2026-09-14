import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// Auto-update Windows : telecharge le zip de la nouvelle release, lance un
/// script PowerShell detache qui attend la fermeture de l'app, remplace les
/// fichiers, puis relance l'exe -- et ferme l'app courante pour liberer le
/// verrou Windows sur vinland.exe (impossible de remplacer un .exe pendant
/// qu'il tourne). Accepte volontairement le risque de faux-positif
/// antivirus/SmartScreen lie a ce type de comportement (decision utilisateur) :
/// pas de mise a jour signee/verifiee au-dela du HTTPS de GitHub.
class SelfUpdaterService {
  /// Retourne false en cas d'echec (rien n'est modifie). En cas de succes,
  /// le processus courant se termine (exit(0)) et ne revient jamais ici.
  Future<bool> downloadAndApply(String downloadUrl) async {
    if (!Platform.isWindows) return false;

    try {
      final tempDir = await Directory.systemTemp.createTemp('vinland_update_');
      final zipPath = p.join(tempDir.path, 'update.zip');

      final response = await http
          .get(Uri.parse(downloadUrl))
          .timeout(const Duration(minutes: 5));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
        return false;
      }
      await File(zipPath).writeAsBytes(response.bodyBytes);

      final exePath = Platform.resolvedExecutable;
      final installDir = File(exePath).parent.path;
      final scriptPath = p.join(tempDir.path, 'vinland_update.ps1');
      await File(scriptPath).writeAsString(_scriptContent);

      await Process.start(
        'powershell.exe',
        [
          '-NoProfile',
          '-ExecutionPolicy', 'Bypass',
          '-WindowStyle', 'Hidden',
          '-File', scriptPath,
          '-ProcessId', pid.toString(),
          '-ZipPath', zipPath,
          '-InstallDir', installDir,
          '-ExePath', exePath,
        ],
        mode: ProcessStartMode.detached,
      );

      exit(0);
    } catch (e) {
      return false;
    }
  }

  static const _scriptContent = r'''
param(
  [int]$ProcessId,
  [string]$ZipPath,
  [string]$InstallDir,
  [string]$ExePath
)

# Log garde a cote de l'exe : le script tourne cache et se supprime lui-meme,
# donc sans ca un echec est totalement invisible (vecu par l'utilisateur
# comme "l'app se ferme et il ne se passe plus rien").
$logPath = Join-Path $InstallDir 'vinland_update.log'
function Log($msg) {
  "$(Get-Date -Format o) $msg" | Out-File -FilePath $logPath -Append -ErrorAction SilentlyContinue
}

# Retry avec backoff : juste apres l'ecriture du nouvel exe (ou pendant la
# fermeture de l'ancien), l'antivirus/Defender peut poser un verrou bref sur
# le fichier -- un seul essai suffit a faire rater la mise a jour en
# silence.
function Invoke-WithRetry([scriptblock]$Action, [string]$Label, [int]$Attempts = 5) {
  for ($i = 1; $i -le $Attempts; $i++) {
    try {
      & $Action
      Log "$Label OK (essai $i)"
      return $true
    } catch {
      Log "$Label echec essai $i : $_"
      Start-Sleep -Seconds 2
    }
  }
  return $false
}

Log "Debut mise a jour : pid=$ProcessId zip=$ZipPath install=$InstallDir exe=$ExePath"

try {
  Wait-Process -Id $ProcessId -Timeout 20 -ErrorAction SilentlyContinue
} catch {}
Start-Sleep -Seconds 1

$extracted = Invoke-WithRetry -Label 'Expand-Archive' -Action {
  Expand-Archive -Path $ZipPath -DestinationPath $InstallDir -Force
}

Remove-Item $ZipPath -ErrorAction SilentlyContinue

$started = Invoke-WithRetry -Label 'Start-Process' -Action {
  Start-Process -FilePath $ExePath
}

Log "Fin : extracted=$extracted started=$started"
Remove-Item $PSCommandPath -ErrorAction SilentlyContinue
''';
}
