import 'dart:io';
import 'package:path/path.dart' as p;

import 'release_signature.dart';
import 'update_check_service.dart';

/// Auto-update Windows : telecharge le zip de la nouvelle release, verifie
/// son empreinte dans le SHA256SUMS signe de la release (voir
/// release_signature.dart), lance un script PowerShell qui attend la
/// fermeture de l'app, remplace les fichiers, puis relance l'exe -- et ferme
/// l'app courante pour liberer le verrou Windows sur vinland.exe (impossible
/// de remplacer un .exe pendant qu'il tourne). Le risque de faux-positif
/// antivirus/SmartScreen lie a ce type de comportement reste accepte
/// (decision utilisateur) ; la signature garantit en revanche que seul un zip
/// publie par release.yml peut etre installe.
class SelfUpdaterService {
  /// Retourne le message d'erreur a afficher en cas d'echec (rien n'est
  /// modifie). En cas de succes, le processus courant se termine (exit(0))
  /// et ne revient jamais ici.
  Future<String?> downloadAndApply(UpdateInfo update) async {
    if (!Platform.isWindows) return 'Mise à jour non disponible ici.';
    final url = update.windowsDownloadUrl;
    if (url == null) return 'Aucun zip Windows dans cette release.';

    try {
      final verified = await downloadVerifiedAsset(
        assetUrl: url,
        checksumsUrl: update.checksumsUrl,
        signatureUrl: update.signatureUrl,
      );

      final tempDir = await Directory.systemTemp.createTemp('vinland_update_');
      final zipPath = p.join(tempDir.path, 'update.zip');
      await File(zipPath).writeAsBytes(verified.bytes);

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
          '-ExecutionPolicy',
          'Bypass',
          '-File',
          scriptPath,
          '-ProcessId',
          pid.toString(),
          '-ZipPath',
          zipPath,
          '-InstallDir',
          installDir,
          '-ExePath',
          exePath,
          // Le script reverifie l'empreinte juste avant d'extraire : le zip
          // attend quelques secondes dans le dossier temporaire, modifiable
          // par n'importe quel programme de la session.
          '-ExpectedSha256',
          verified.sha256,
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
      if (!await _isPidAlive(proc.pid)) {
        return 'Le script de mise à jour a été bloqué (antivirus ?), '
            'réessaie plus tard.';
      }

      exit(0);
    } on ReleaseVerificationException catch (e) {
      return e.message;
    } catch (e) {
      return 'Échec de la mise à jour automatique, réessaie plus tard.';
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
  [string]$ExePath,
  [string]$ExpectedSha256
)

# Log garde a cote de l'exe : le script tourne cache et se supprime lui-meme,
# donc sans ca un echec est totalement invisible (vecu par l'utilisateur
# comme "l'app se ferme et il ne se passe plus rien").
$logName = 'vinland_update.log'
$logPath = Join-Path $InstallDir $logName
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

# En cas d'echec on relance quand meme l'ancienne version : l'utilisateur
# retrouve son app au lieu d'une fenetre fermee.
function Exit-WithOldVersion([string]$reason) {
  Log "Abandon : $reason"
  Remove-Item $ZipPath -ErrorAction SilentlyContinue
  if ($staging) { Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue }
  try { Start-Process -FilePath $ExePath -ErrorAction Stop } catch { Log "Relance impossible : $_" }
  Remove-Item $PSCommandPath -ErrorAction SilentlyContinue
  exit 1
}

Log "Debut mise a jour : pid=$ProcessId zip=$ZipPath install=$InstallDir exe=$ExePath"

try {
  Wait-Process -Id $ProcessId -Timeout 20 -ErrorAction SilentlyContinue
} catch {}
Start-Sleep -Seconds 1

# L'app a deja verifie la signature et l'empreinte ; on recompare ici car le
# zip a attendu dans le dossier temporaire pendant la fermeture de l'app.
$staging = $null
$actual = (Get-FileHash -Algorithm SHA256 -Path $ZipPath -ErrorAction SilentlyContinue).Hash
if (-not $ExpectedSha256 -or $actual -ne $ExpectedSha256) {
  Exit-WithOldVersion "empreinte du zip inattendue ($actual)"
}

# Extraction dans un dossier temporaire d'abord : un zip incomplet ne touche
# pas a l'installation, et on remplace ensuite tout le dossier au lieu
# d'ecraser fichier par fichier (sinon les fichiers supprimes d'une version
# a l'autre restaient la indefiniment).
$staging = Join-Path ([System.IO.Path]::GetTempPath()) ("vinland_staging_" + [guid]::NewGuid().ToString('N'))
$extracted = Invoke-WithRetry -Label 'Expand-Archive' -Action {
  Expand-Archive -Path $ZipPath -DestinationPath $staging -Force -ErrorAction Stop
}
$exeName = Split-Path $ExePath -Leaf
if (-not $extracted -or -not (Test-Path (Join-Path $staging $exeName))) {
  Exit-WithOldVersion "zip illisible ou sans $exeName"
}

# L'ancienne version est mise de cote dans un sous-dossier (meme disque, donc
# simple renommage) pour pouvoir revenir en arriere si la copie echoue.
$backupName = '.vinland_old'
$backup = Join-Path $InstallDir $backupName
Remove-Item $backup -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $backup -Force | Out-Null

function Restore-Backup {
  Get-ChildItem -LiteralPath $InstallDir -Force |
    Where-Object { $_.Name -ne $backupName -and $_.Name -ne $logName } |
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
  Get-ChildItem -LiteralPath $backup -Force |
    Move-Item -Destination $InstallDir -Force -ErrorAction SilentlyContinue
  Remove-Item $backup -Recurse -Force -ErrorAction SilentlyContinue
}

$moved = Invoke-WithRetry -Label 'Move-Item ancienne version' -Action {
  Get-ChildItem -LiteralPath $InstallDir -Force |
    Where-Object { $_.Name -ne $backupName -and $_.Name -ne $logName } |
    Move-Item -Destination $backup -Force -ErrorAction Stop
}
if (-not $moved) {
  Restore-Backup
  Exit-WithOldVersion 'ancienne version verrouillee'
}

$copied = Invoke-WithRetry -Label 'Copy-Item nouvelle version' -Action {
  Get-ChildItem -LiteralPath $staging -Force |
    Copy-Item -Destination $InstallDir -Recurse -Force -ErrorAction Stop
}
if (-not $copied) {
  Restore-Backup
  Exit-WithOldVersion 'copie de la nouvelle version impossible'
}

Remove-Item $backup -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $ZipPath -ErrorAction SilentlyContinue

$started = Invoke-WithRetry -Label 'Start-Process' -Action {
  Start-Process -FilePath $ExePath
}

Log "Fin : started=$started"
Remove-Item $PSCommandPath -ErrorAction SilentlyContinue
''';
}
