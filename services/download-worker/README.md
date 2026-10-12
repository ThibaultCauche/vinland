# download-worker

Service de telechargement automatique : l'app lui envoie « artiste - titre »
pour un morceau trouve via Deezer mais absent du NAS, il le cherche (Lidarr,
puis spotdl en secours), harmonise les tags (beets), le range dans la
bibliotheque Navidrome et renvoie son id Subsonic. Il recoit aussi les
imports de fichiers locaux depuis l'app.

> Le code (`server.py`, `lidarr.py`, `beets_tagger.py`...) doit encore etre
> copie ici depuis le NAS : voir « Ajouter le code des services » dans
> `services/README.md`.

Client dans l'app : `lib/services/download_worker_service.dart`.
