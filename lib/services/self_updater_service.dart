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

      // mode: normal, PAS detached -- teste et confirme en conditions reelles
      // (2026-09-15) que ProcessStartMode.detached fait mourir powershell.exe
      // en quelques millisecondes sur Windows (avant meme d'ecrire sa
      // premiere ligne de log), ce qui faisait echouer l'auto-update a
      // chaque fois (silencieusement avant l'ajout du message d'erreur,
      // "Echec de la mise a jour automatique" ensuite). mode: normal marche
      // de facon fiable ET le processus survit bien a exit(0) juste apres
      // (verifie : un process enfant Windows n'est pas tue par la sortie de
      // son parent, contrairement a un modele Unix avec groupe de process) --
      // detached n'etait donc pas necessaire pour ce que ce code doit faire.
      final proc = await Process.start(
        'powershell.exe',
        [
          '-NoProfile',
          '-ExecutionPolicy', 'Bypass',
          '-File', scriptPath,
          '-ProcessId', pid.toString(),
          '-ZipPath', zipPath,
          '-InstallDir', installDir,
          '-ExePath', exePath,
        ],
        mode: ProcessStartMode.normal,
      );

      // Verifie que le script est toujours vivant avant de fermer l'app :
      // un antivirus/SmartScreen qui le tue au demarrage (profil suspect --
      // PowerShell avec policy bypass juste apres un exe fraichement
      // telecharge, donc marque "Internet" par Windows) le fait dans les
      // toutes premieres millisecondes. Sans cette verification, l'app se
      // fermait quand meme (exit(0) inconditionnel) : l'utilisateur ne
      // voyait plus qu'une fenetre fermee et plus rien ensuite, sans le
      // moindre message -- le pire des deux mondes. Ici, si le process est
      // deja mort, on annule et on laisse l'app ouverte avec un message
      // d'echec explicite (voir update_prompt.dart) au lieu de fermer pour
      // rien.
      // Pas via proc.exitCode : un process detache leve "Bad state: Process
      // is detached" (Dart n'en garde pas le handle) -- il faut demander a
      // Windows lui-meme si ce PID existe encore.
      await Future.delayed(const Duration(milliseconds: 800));
      if (!await _isPidAlive(proc.pid)) return false;

      exit(0);
    } catch (e) {
      return false;
    }
  }

  Future<bool> _isPidAlive(int pid) async {
    try {
      final result =
          await Process.run('tasklist', ['/FI', 'PID eq $pid', '/NH']);
      return (result.stdout as String).contains(pid.toString());
    } catch (_) {
      // Verification elle-meme en echec (tasklist introuvable...) : on
      // suppose que le process va bien plutot que de bloquer une mise a
      // jour qui aurait fonctionne.
      return true;
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
