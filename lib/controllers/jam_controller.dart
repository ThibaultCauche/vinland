import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../data/track_repository.dart';
import '../domain/jam_sync.dart';
import '../models/track.dart';
import '../services/jam_service.dart';
import 'jam_playback.dart';
import 'jam_sync_settings.dart';

/// Jam entre amis et synchro perso multi-appareils : hebergement,
/// participation, application de l'etat de l'hote, battement, commandes a
/// distance, transfert d'hebergement.
///
/// Pilote la lecture locale a travers [JamPlayback] (PlayerController dans
/// l'app) ; AppState lui demande, avant chaque action de lecture, si le Jam
/// la prend en charge (voir les methodes `intercept*`). Le relais et la
/// bibliotheque sont injectes pour pouvoir tester deux appareils en memoire
/// (voir test/controllers/jam_controller_test.dart).
class JamController extends ChangeNotifier {
  JamController({
    required JamService jam,
    required JamPlayback playback,
    required TrackRepository tracks,
    required String? Function() username,
    required String deviceLabel,
    JamSyncSettings? syncSettings,
    this.syncPolicy = const SyncPolicy(),
    this.heartbeatInterval = const Duration(seconds: 2),
    this.personalSyncPollInterval = const Duration(seconds: 20),
  })  : _jam = jam,
        _playback = playback,
        _tracks = tracks,
        _username = username,
        _deviceLabel = deviceLabel,
        syncSettings = syncSettings ?? JamSyncSettings() {
    this.syncSettings.addListener(_onOffsetChanged);
  }

  final JamService _jam;
  final JamPlayback _playback;
  final TrackRepository _tracks;
  final String? Function() _username;
  final String _deviceLabel;

  /// Cadence a laquelle l'hote rediffuse son etat (voir broadcastState) et
  /// donc a laquelle chaque participant mesure son ecart (voir
  /// _applyJamState). Descendu de 5s a 2s (retour utilisateur : leger
  /// decalage constant percu entre deux appareils).
  final Duration heartbeatInterval;

  /// Decalage audio de cet appareil (latence Bluetooth), voir
  /// JamSyncSettings.
  final JamSyncSettings syncSettings;

  /// Seuils seek / vitesse / rien, voir decideSync.
  final SyncPolicy syncPolicy;

  /// Ecart mesure a chaque etat recu de l'hote, pour l'ecran cache
  /// JamSyncDebugScreen.
  final SyncLog syncLog = SyncLog();

  /// Ecart d'horloge avec le relais (journal).
  ClockEstimate get clock => _jam.clock;

  /// Vitesse demandee au lecteur en dernier (1 hors rattrapage) : evite
  /// de lui renvoyer la meme valeur a chaque battement.
  double currentSpeed = 1;

  /// Dernier etat recu de l'hote : rejoue tout de suite quand le decalage
  /// manuel change, pour qu'on entende l'effet du reglage sans attendre.
  JamStateMessage? _lastHostState;

  /// Voir startPersonalSyncPolling.
  final Duration personalSyncPollInterval;

  /// Le role d'hote vient de changer (demarrage, depart, transfert) : AppState
  /// republie son mirroir "now playing", qui annonce le sessionId quand on
  /// heberge.
  void Function()? onHostingChanged;

  bool get isActive => _jam.isActive;
  bool get isHost => _jam.isHost;
  String? get sessionId => _jam.sessionId;
  int participantCount = 0;

  /// Pseudos des participants actuels (voir JamService.participantsStream),
  /// utilise pour le picker "Ceder l'hebergement" (voir showJamMenu). Vide
  /// hors session ou tant qu'on n'est pas hote.
  List<String> participantUsernames = [];

  /// Exclut son propre pseudo : les autres appareils du meme compte suivent
  /// silencieusement en synchro perso (voir isPersonalSyncParticipant) et
  /// partagent donc le meme pseudo Navidrome que l'hote -- jamais une cible
  /// valide pour un transfert d'hebergement (ils ne jouent jamais l'audio
  /// localement, voir _applyPersonalSyncState).
  List<String> get transferTargets =>
      participantUsernames.where((u) => u != _username()).toList();

  StreamSubscription? _stateSub;
  StreamSubscription? _hostLeftSub;
  StreamSubscription? _countSub;
  StreamSubscription? _participantsSub;
  StreamSubscription? _commandSub;
  StreamSubscription? _roleChangeSub;
  Timer? _heartbeat;
  Timer? _personalSyncPoll;
  bool _applyingJamState = false;
  bool _disposed = false;

  // Synchro multi-appareils "perso" (voir onLocalTrackStarted /
  // _tryJoinPersonalSync) : reutilise le relais Jam mais avec une session
  // deterministe par compte (pas de code a partager) et, cote participant,
  // affichage + controle a distance seulement -- l'audio n'est jamais joue
  // en double, contrairement au Jam "entre amis" classique.
  bool _personalSyncMode = false;
  Track? remoteTrack;
  bool remoteIsPlaying = false;
  String? remoteDeviceName;
  Duration? remotePosition;
  bool get isPersonalSyncParticipant =>
      _personalSyncMode && isActive && !isHost;
  bool get isPersonalSyncHost => _personalSyncMode && isHost;

  /// Vrai seulement pour une session Jam "entre amis" demarree/rejointe
  /// manuellement (menu Jam) -- exclut la synchro perso multi-appareils
  /// (silencieuse, jamais affichee dans ce menu). Utilise par
  /// jam_controls.dart et l'icone Jam de la barre de lecture desktop.
  bool get isFriendJamActive => isActive && !_personalSyncMode;

  /// Participant d'un Jam entre amis : suit passivement l'hote, toute action
  /// de lecture locale est ignoree -- sauf celles faites par _applyJamState
  /// lui-meme pour suivre l'hote.
  bool get _followsHost => isActive && !isHost && !_applyingJamState;

  /// Nom de l'appareil participant actuellement connecte a NOTRE synchro
  /// perso (voir isPersonalSyncHost) -- annonce par lui via la commande
  /// 'announce_device' (voir _announceDeviceToHost/_applyCommand), pas
  /// connu du relais (voir jam_relay/, qui ne suit que des pseudos, memes
  /// pour tous les appareils du meme compte). Sert uniquement a afficher
  /// "Connecte : <appareil>" dans showDeviceMenu -- le controle a distance
  /// marche deja sans ca, c'est juste pour que l'hote voie que l'autre
  /// appareil l'a bien detecte (retour utilisateur : "je ne vois pas le PC
  /// alors qu'il controle deja ma lecture").
  String? connectedParticipantDeviceName;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  // --- Gardes devant la lecture locale ---------------------------------
  //
  // Chaque methode renvoie true quand le Jam a pris l'action en charge (ou
  // l'a ignoree) : AppState ne doit alors PAS la transmettre au lecteur.

  bool interceptPlayTrack(Track track) {
    // Participant de synchro perso (voir isPersonalSyncParticipant) : ne
    // joue jamais ce titre localement (ce qui aurait silencieusement pris
    // le role d'hote, voir onLocalTrackStarted) -- demande plutot a
    // l'appareil deja actif de le jouer, lui (retour utilisateur : "vice
    // versa", changer de titre depuis n'importe quel appareil doit piloter
    // celui qui joue vraiment, pas en prendre le controle).
    if (isPersonalSyncParticipant && !_applyingJamState) {
      remotePlayTrack(track);
      return true;
    }
    return _followsHost;
  }

  bool interceptTogglePlayPause() {
    if (isPersonalSyncParticipant) {
      remoteToggle();
      return true;
    }
    return _followsHost;
  }

  bool interceptNext() {
    if (isPersonalSyncParticipant) {
      remoteNext();
      return true;
    }
    return _followsHost;
  }

  bool interceptPrevious() {
    if (isPersonalSyncParticipant) {
      remotePrevious();
      return true;
    }
    return _followsHost;
  }

  bool interceptSeek(Duration pos) {
    if (isPersonalSyncParticipant) {
      remoteSeek(pos);
      return true;
    }
    return _followsHost;
  }

  /// "Ajouter a la file d'attente" chez un participant de Jam : sa file
  /// locale n'est jamais lue tant qu'il suit un hote, donc on relaie la
  /// demande a l'hote (voir _applyCommand) plutot que de se contenter d'un
  /// ajout local inerte.
  void relayAddToQueue(Track track) {
    if (isActive && !isHost) _jam.sendCommand('queue_add', trackId: track.id);
  }

  /// Meme relais que relayAddToQueue pour "Lire ensuite".
  void relayPlayNext(Track track) {
    if (isActive && !isHost) _jam.sendCommand('play_next', trackId: track.id);
  }

  // --- Jam entre amis ---------------------------------------------------

  /// Demarre une session Jam en tant qu'hote : pilote la lecture normalement,
  /// diffuse son etat (titre/position/lecture-pause) aux participants via le
  /// relais (voir jam_relay/) a chaque changement et a chaque battement pour
  /// rattraper la derive. Renvoie le sessionId a partager, ou null en cas
  /// d'echec (relais injoignable).
  Future<String?> startSession() async {
    _personalSyncMode = false;
    _clearRemote();
    final id = _jam.generateSessionId();
    final ok = await _jam.host(id);
    if (!ok) return null;
    _wireAsHost();
    _listenForHostTransfer();
    broadcastState();
    if (_playback.currentTrack != null) onHostingChanged?.call();
    _notify();
    return id;
  }

  /// Abonnements communs a toute prise du role d'hote (demarrage explicite,
  /// synchro perso, ou promotion via un transfert -- voir
  /// _applyHostTransfer) : compteur/pseudos des participants, commandes a
  /// distance (play/pause, ajout a la file), battement de resynchronisation.
  void _wireAsHost() {
    _countSub?.cancel();
    _countSub = _jam.participantCountStream.listen((count) {
      participantCount = count;
      // Un participant qui vient de rejoindre n'a jamais reçu la file
      // d'attente : force son renvoi au prochain battement (voir
      // broadcastState) meme si son contenu n'a pas change depuis le
      // dernier envoi aux participants deja presents.
      _lastBroadcastQueueIds = null;
      // Plus personne connecte : oublie l'appareil annonce precedemment
      // (voir connectedParticipantDeviceName) -- sinon showDeviceMenu
      // continuait d'afficher "Connecte : Téléphone" longtemps apres sa
      // deconnexion.
      if (count == 0) connectedParticipantDeviceName = null;
      _notify();
    });
    _participantsSub?.cancel();
    _participantsSub = _jam.participantsStream.listen((names) {
      participantUsernames = names;
      _notify();
    });
    // Sans ca, les commandes envoyees par les participants (play/pause a
    // distance, ajout a la file -- voir sendCommand/_applyCommand)
    // n'etaient recues que dans la synchro perso multi-appareils : un vrai
    // Jam entre amis les ignorait silencieusement, l'hote ne les ecoutant
    // jamais.
    _commandSub?.cancel();
    _commandSub = _jam.commandStream.listen(_applyCommand);
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(heartbeatInterval, (_) => broadcastState());
  }

  /// Rejoint une session Jam existante : suit passivement l'etat de l'hote
  /// (voir _applyJamState), les actions de lecture locales sont ignorees
  /// tant que la session est active (voir les methodes intercept*).
  Future<bool> joinSession(String sessionId) async {
    _personalSyncMode = false;
    final ok = await _jam.join(sessionId);
    if (!ok) return false;
    _followFriendHost();
    _listenForHostTransfer();
    _notify();
    return true;
  }

  void _followFriendHost() {
    _stateSub?.cancel();
    _stateSub = _jam.stateStream.listen(_applyJamState);
    _hostLeftSub?.cancel();
    _hostLeftSub = _jam.hostLeftStream.listen((_) => leaveSession());
  }

  void _listenForHostTransfer() {
    _roleChangeSub?.cancel();
    _roleChangeSub = _jam.hostTransferredStream.listen(_applyHostTransfer);
  }

  /// Cede l'hebergement a `targetUsername` (voir transferTargets) --
  /// reserve a l'hote actuel. Les deux appareils basculent de role via
  /// _applyHostTransfer des que le relais confirme (voir
  /// JamService.hostTransferredStream) ; les autres participants ne
  /// remarquent que le prochain 'state' vient d'ailleurs.
  void transferHost(String targetUsername) {
    if (!isHost) return;
    _jam.sendTransferHost(targetUsername);
  }

  /// Bascule de role suite a un transfert d'hebergement confirme par le
  /// relais (voir transferHost/JamService.hostTransferredStream) : la
  /// session WebSocket reste la meme, seul le role change ici --
  /// contrairement a startSession/joinSession, qui (re)ouvrent une
  /// connexion. L'audio ne s'interrompt jamais : le nouvel hote jouait deja
  /// localement ce titre en le suivant (voir _applyJamState), il continue
  /// simplement a le piloter au lieu de le suivre.
  void _applyHostTransfer(bool becameHost) {
    if (becameHost) {
      _lastHostState = null;
      // Le nouvel hote est la reference : il ne rattrape plus personne.
      unawaited(_setSpeed(1));
      _stateSub?.cancel();
      _stateSub = null;
      _hostLeftSub?.cancel();
      _hostLeftSub = null;
      _wireAsHost();
      _lastBroadcastQueueIds = null;
      broadcastState();
    } else {
      // Ce callback est partage par deux cas bien distincts qui envoient
      // tous les deux un 'host_transferred' cote relais (voir le cas 'host'
      // dans jam_relay/bin/server.dart, "prise de controle" y compris) :
      // 1. un vrai transfert d'hebergement Jam entre amis (voir
      //    transferHost) -- celui qui le recoit doit redevenir un vrai
      //    suiveur Jam (isFriendJamActive, actions locales ignorees).
      // 2. un autre appareil du MEME compte qui "reprend ici" la synchro
      //    perso (voir takeOverPersonalSync/onLocalTrackStarted) --
      //    celui-ci doit rester un participant de synchro perso normal
      //    (menu Peripheriques, remoteToggle/remoteNext...), pas basculer en
      //    suiveur Jam : sans cette distinction, l'appareil retrograde
      //    perdait _personalSyncMode et donc isPersonalSyncParticipant, se
      //    retrouvant coince en suiveur Jam muet -- plus aucun controle,
      //    plus aucune detection de periphérique (retour utilisateur).
      // _personalSyncMode est le seul signal disponible pour les separer :
      // vrai seulement si CET appareil etait lui-meme l'hote de la synchro
      // perso avant ce transfert.
      final wasPersonalHost = _personalSyncMode;
      _unwireHost();
      if (wasPersonalHost) {
        _followPersonalHost();
      } else {
        _personalSyncMode = false;
        _followFriendHost();
      }
    }
    onHostingChanged?.call();
    _notify();
  }

  void _unwireHost() {
    _heartbeat?.cancel();
    _heartbeat = null;
    _commandSub?.cancel();
    _commandSub = null;
    _countSub?.cancel();
    _countSub = null;
    _participantsSub?.cancel();
    _participantsSub = null;
    participantCount = 0;
    participantUsernames = [];
  }

  Future<void> leaveSession() async {
    final wasHost = isHost;
    await _closeSession();
    if (wasHost && _playback.currentTrack != null) onHostingChanged?.call();
    _notify();
  }

  /// Coupe tout (abonnements, battement, connexion) sans prevenir AppState :
  /// deconnexion du compte et fermeture de l'app. Sans ca, une session Jam
  /// active survivait a la deconnexion : le compte qui se reconnecte ensuite
  /// heritait d'une session WebSocket ouverte sous une identite qui n'est
  /// plus la sienne.
  Future<void> disconnect() async {
    await _closeSession();
    _notify();
  }

  Future<void> _closeSession() async {
    _personalSyncMode = false;
    _lastHostState = null;
    // Sans ca, un participant qui quittait en plein rattrapage gardait sa
    // lecture a 103 % pour la suite de la soiree.
    await _setSpeed(1);
    _clearRemote();
    _unwireHost();
    await _stateSub?.cancel();
    _stateSub = null;
    await _hostLeftSub?.cancel();
    _hostLeftSub = null;
    await _roleChangeSub?.cancel();
    _roleChangeSub = null;
    await _jam.leave();
  }

  /// Derniere file d'attente envoyee aux participants (voir
  /// broadcastState) : evite de rerepeter potentiellement des milliers
  /// d'ids a chaque battement quand elle n'a pas change.
  List<String>? _lastBroadcastQueueIds;

  /// Diffuse l'etat de lecture local aux participants. Sans effet tant qu'on
  /// n'heberge pas : AppState l'appelle a chaque evenement du moteur audio.
  void broadcastState() {
    if (!_jam.isActive || !_jam.isHost) return;
    final track = _playback.currentTrack;
    if (track == null) return;
    final currentQueueIds = _playback.queue.map((t) => t.id).toList();
    final queueChanged = !listEquals(_lastBroadcastQueueIds, currentQueueIds);
    if (queueChanged) _lastBroadcastQueueIds = currentQueueIds;
    // Position reellement entendue : celle du lecteur moins la latence de
    // la sortie audio de l'hote (voir JamSyncSettings). Chaque participant
    // ajoute ensuite la sienne (voir _applyJamState).
    final heardMs = _playback.livePosition.inMilliseconds -
        syncSettings.offset.inMilliseconds;
    _jam.sendState(
      trackId: track.id,
      positionMs: math.max(0, heardMs),
      isPlaying: _playback.isPlaying,
      deviceName: _deviceLabel,
      queueIds: queueChanged ? currentQueueIds : null,
    );
  }

  /// Applique l'etat recu de l'hote (voir joinSession) : change de titre
  /// si besoin, mesure l'ecart avec la position de l'hote et le corrige
  /// (voir decideSync : seek si > 1 s, vitesse +/-3 % entre 40 ms et 1 s,
  /// rien en dessous), aligne play/pause, et reflete la vraie file
  /// d'attente de l'hote (voir msg.queueIds) -- sans ca, chaque participant
  /// gardait sa propre file locale, jamais reliee a ce qui joue vraiment
  /// (retour utilisateur : "chacun a sa file d'attente"). _applyingJamState
  /// laisse passer ces appels a travers les gardes intercept*, qui bloquent
  /// sinon toute action de lecture locale pendant une session suivie.
  ///
  /// Avant la session 15, chaque battement faisait un seek : sur un flux
  /// distant ca relancait une requete et coupait le son, et le temps de
  /// transit etait calcule avec deux horloges jamais reglees pareil.
  Future<void> _applyJamState(JamStateMessage msg,
      {bool forceSeek = false}) async {
    _lastHostState = msg;
    _applyingJamState = true;
    try {
      var trackChanged = false;
      if (_playback.currentTrack?.id != msg.trackId) {
        final track = _tracks.findById(msg.trackId);
        if (track != null) {
          await _playback.playTrack(track, trackList: [track]);
          trackChanged = true;
        }
      }
      final wasPlaying = _playback.isPlaying;
      // Transit et chargement depuis l'envoi, en heure du relais des deux
      // cotes (voir JamService.relayNowMs). Borne : un etat vieux de plus
      // de 5 s (appareil en veille) ne doit pas faire sauter loin devant.
      final elapsedMs = msg.isPlaying
          ? (_jam.relayNowMs() - msg.ts).clamp(0, 5000).toInt()
          : 0;
      final offsetMs = msg.isPlaying ? syncSettings.offset.inMilliseconds : 0;
      final expected = Duration(
          milliseconds: math.max(0, msg.positionMs + elapsedMs + offsetMs));
      final drift = expected - _playback.livePosition;
      // A l'arret, au demarrage ou sur un nouveau titre, un seek ne
      // s'entend pas : on se cale directement, sans passer par la vitesse.
      final silent = forceSeek || trackChanged || !msg.isPlaying || !wasPlaying;
      var action = decideSync(drift, expected: expected, policy: syncPolicy);
      if (silent && action is SyncNudge) action = SyncSeek(expected);
      switch (action) {
        case SyncSeek(:final target):
          await _setSpeed(1);
          _playback.seek(target);
        case SyncNudge(:final speed):
          await _setSpeed(speed);
        case SyncHold():
          await _setSpeed(1);
      }
      if (msg.isPlaying) _logDrift(drift, action);
      await _playback.setPlaying(msg.isPlaying);
      if (msg.queueIds != null) {
        _playback.replaceQueue(
            msg.queueIds!.map(_tracks.findById).whereType<Track>().toList());
      }
    } finally {
      _applyingJamState = false;
    }
  }

  Future<void> _setSpeed(double speed) async {
    if (speed == currentSpeed) return;
    currentSpeed = speed;
    await _playback.setSpeed(speed);
  }

  void _logDrift(Duration drift, SyncAction action) {
    final clock = _jam.clock;
    syncLog.add(SyncLogEntry(
      at: DateTime.now(),
      driftMs: drift.inMilliseconds,
      action: action,
      clockOffsetMs: clock.offsetMs,
      roundTripMs: clock.roundTripMs,
    ));
    _notify();
  }

  void clearSyncLog() {
    syncLog.clear();
    _notify();
  }

  /// Le decalage manuel vient de changer (curseur du menu Jam) : on se
  /// recale tout de suite sur le dernier etat de l'hote, plutot que de
  /// laisser la vitesse rattraper en plusieurs secondes -- celui qui regle
  /// doit entendre l'effet pour trouver la bonne valeur.
  void _onOffsetChanged() {
    final last = _lastHostState;
    if (last == null || !isActive || isHost || _personalSyncMode) {
      _notify();
      return;
    }
    unawaited(_applyJamState(last, forceSeek: true));
  }

  // --- Synchro perso multi-appareils ------------------------------------

  /// Sondage periodique (voir AppState.initialize) : tant qu'aucune session
  /// Jam n'est active, tente de rejoindre la synchro perso de ce compte --
  /// si un autre appareil est deja hote, on le retrouve automatiquement sans
  /// action utilisateur, meme si cet appareil-ci n'etait pas ouvert quand
  /// l'autre a demarre sa lecture.
  // ponytail: sondage simple (toutes les 20s) plutot qu'un mecanisme de
  // presence -- suffisant a l'echelle d'un usage personnel multi-appareils,
  // a revoir si ca devient sensible a la latence/batterie.
  void startPersonalSyncPolling() {
    _personalSyncPoll?.cancel();
    _personalSyncPoll = Timer.periodic(
        personalSyncPollInterval, (_) => unawaited(_tryJoinPersonalSync()));
    unawaited(_tryJoinPersonalSync());
  }

  Future<void> _tryJoinPersonalSync() async {
    if (isActive) return;
    final username = _username();
    if (username == null) return;
    final id = _jam.personalSessionId(username);
    final ok = await _jam.join(id);
    if (!ok) return;
    _followPersonalHost();
    _notify();
  }

  void _followPersonalHost() {
    _personalSyncMode = true;
    _stateSub?.cancel();
    _stateSub = _jam.stateStream.listen(_applyPersonalSyncState);
    _hostLeftSub?.cancel();
    _hostLeftSub = _jam.hostLeftStream.listen((_) => _leavePersonalSync());
    _announceDeviceToHost();
  }

  /// Affiche seulement l'etat recu d'un autre appareil du meme compte --
  /// contrairement a _applyJamState (Jam entre amis), ne joue jamais l'audio
  /// localement : voir remoteTrack/remoteIsPlaying/remoteDeviceName et les
  /// boutons de la barre de lecture qui pilotent l'hote via remoteToggle/
  /// remoteNext/remotePrevious plutot que le moteur audio local.
  void _applyPersonalSyncState(JamStateMessage msg) {
    remoteTrack = _tracks.findById(msg.trackId);
    remoteIsPlaying = msg.isPlaying;
    remoteDeviceName = msg.deviceName;
    remotePosition = Duration(milliseconds: msg.positionMs);
    _notify();
  }

  void _clearRemote() {
    remoteTrack = null;
    remoteIsPlaying = false;
    remoteDeviceName = null;
    remotePosition = null;
  }

  Future<void> _leavePersonalSync() async {
    _personalSyncMode = false;
    _clearRemote();
    await _stateSub?.cancel();
    _stateSub = null;
    await _hostLeftSub?.cancel();
    _hostLeftSub = null;
    await _jam.leave();
    _notify();
  }

  /// "Reprendre ici" depuis le menu Peripheriques (voir showDeviceMenu) :
  /// bascule le titre en cours d'ecoute sur un autre appareil du compte vers
  /// celui-ci, a la position ou l'autre appareil en etait. Jouer localement
  /// prend deja seul l'hote de la synchro perso (voir onLocalTrackStarted),
  /// exactement comme changer d'appareil actif dans Spotify Connect -- il
  /// suffit donc de lancer le titre distant puis de rattraper sa position.
  ///
  /// Passe directement par le lecteur, sans les gardes intercept* : en tant
  /// que participant, playTrack etait renvoye a l'hote (remotePlayTrack),
  /// qui rejouait son propre titre, et "Reprendre ici" ne reprenait rien.
  Future<void> takeOverPersonalSync() async {
    final track = remoteTrack;
    if (track == null) return;
    final resumePosition = remotePosition;
    await _playback.playTrack(track);
    if (resumePosition != null && resumePosition > Duration.zero) {
      _playback.seek(resumePosition);
    }
  }

  /// Prend (ou garde) le role d'hote de la synchro perso a chaque lecture
  /// locale reelle (AppState l'appelle quand un titre demarre) -- jamais
  /// pendant une session Jam entre amis manuelle. C'est ce qui fait
  /// qu'appuyer sur play sur n'importe quel appareil du compte le rend
  /// autoritaire, exactement comme changer d'appareil actif dans Spotify
  /// Connect. Cette session (id prive, voir JamService.personalSessionId)
  /// est republiee dans le mirroir "now playing" (voir onHostingChanged) des
  /// qu'elle est active : c'est ce qui rend n'importe quelle ecoute en cours
  /// rejoignable par un ami depuis la page Amis (bouton "Rejoindre") sans
  /// avoir a demarrer explicitement une session Jam -- "ecoute a la
  /// demande".
  Future<void> onLocalTrackStarted() async {
    // Hote (Jam entre amis compris) : diffuse le nouveau titre tout de suite
    // plutot qu'au prochain evenement du moteur ou battement.
    if (isActive && isHost) {
      broadcastState();
      return;
    }
    if (isActive && !_personalSyncMode) return;
    final username = _username();
    if (username == null) return;
    await _stateSub?.cancel();
    _stateSub = null;
    await _hostLeftSub?.cancel();
    _hostLeftSub = null;
    _clearRemote();

    final id = _jam.personalSessionId(username);
    final ok = await _jam.host(id);
    if (!ok) return;
    _personalSyncMode = true;
    _wireAsHost();
    _listenForHostTransfer();
    broadcastState();
    // Republie tout de suite avec le sessionId maintenant connu -- sans
    // ca, le mirroir publie juste avant par AppState (avant que ce host ne
    // soit etabli) annoncait ce titre sans session, et il fallait attendre
    // jusqu'a 60s (son battement) avant qu'un ami le voie comme rejoignable.
    onHostingChanged?.call();
    _notify();
  }

  void _applyCommand(JamCommandMessage cmd) {
    switch (cmd.action) {
      case 'toggle':
        if (_playback.togglePlayPause()) broadcastState();
        break;
      case 'next':
        unawaited(_playback.next());
        break;
      case 'previous':
        unawaited(_playback.previous());
        break;
      case 'queue_add':
      case 'play_next':
        final track =
            cmd.trackId == null ? null : _tracks.findById(cmd.trackId!);
        if (track == null) return;
        if (cmd.action == 'play_next') {
          _playback.playNext(track);
        } else {
          _playback.addToQueue(track);
        }
        break;
      case 'play_track':
        // Changement de titre demande par un participant de synchro perso
        // (voir remotePlayTrack) : contrairement a queue_add/play_next, on
        // veut vraiment lancer ce titre tout de suite, comme si on l'avait
        // tape localement sur l'hote.
        final track =
            cmd.trackId == null ? null : _tracks.findById(cmd.trackId!);
        if (track == null) return;
        unawaited(_playback.playTrack(track));
        break;
      case 'seek':
        if (cmd.positionMs == null) return;
        _playback.seek(Duration(milliseconds: cmd.positionMs!));
        break;
      case 'announce_device':
        // Purement informatif (voir connectedParticipantDeviceName) : ne
        // pilote rien, juste pour que l'hote sache quel appareil le
        // controle deja (retour utilisateur).
        connectedParticipantDeviceName = cmd.deviceName;
        _notify();
        break;
    }
  }

  /// Fait savoir a l'hote quel appareil vient de le rejoindre en synchro
  /// perso (voir connectedParticipantDeviceName) -- appele juste apres
  /// chaque bascule vers le role de participant (_tryJoinPersonalSync et le
  /// cas "reprise" de _applyHostTransfer), jamais au demarrage d'un Jam
  /// entre amis (l'hote y connait deja tout le monde par pseudo).
  void _announceDeviceToHost() {
    _jam.sendCommand('announce_device', deviceName: _deviceLabel);
  }

  /// Controles de la barre de lecture cote appareil "spectateur" (voir
  /// isPersonalSyncParticipant) : n'agissent jamais sur le moteur audio
  /// local, envoient une commande a l'appareil hote via le relais.
  void remoteToggle() {
    if (!isPersonalSyncParticipant) return;
    _jam.sendCommand('toggle');
  }

  void remoteNext() {
    if (!isPersonalSyncParticipant) return;
    _jam.sendCommand('next');
  }

  void remotePrevious() {
    if (!isPersonalSyncParticipant) return;
    _jam.sendCommand('previous');
  }

  void remoteSeek(Duration pos) {
    if (!isPersonalSyncParticipant) return;
    _jam.sendCommand('seek', positionMs: pos.inMilliseconds);
    // Anticipe localement (comme _applyJamState) au lieu d'attendre le
    // prochain battement de l'hote pour que la barre de progression
    // reflete tout de suite le glissement.
    remotePosition = pos;
    _notify();
  }

  /// "Changer de musique" a distance (voir showDeviceMenu/PlayerScreen) :
  /// demande a l'hote de lancer CE titre tout de suite, plutot que de le
  /// jouer localement -- un participant qui tapait un titre prenait
  /// autrefois silencieusement le role d'hote (voir onLocalTrackStarted)
  /// au lieu de simplement piloter l'appareil deja actif, ce qui n'est pas
  /// ce qu'on attend d'une vraie ecoute Spotify Connect-like entre
  /// plusieurs appareils du meme compte (retour utilisateur).
  void remotePlayTrack(Track track) {
    if (!isPersonalSyncParticipant) return;
    _jam.sendCommand('play_track', trackId: track.id);
  }

  @override
  void dispose() {
    _disposed = true;
    syncSettings.removeListener(_onOffsetChanged);
    _personalSyncPoll?.cancel();
    unawaited(_closeSession());
    super.dispose();
  }
}
