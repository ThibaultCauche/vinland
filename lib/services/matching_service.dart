import 'package:diacritic/diacritic.dart';

/// Logique de comparaison NAS / Deezer / CSV partagee par tout ce qui doit
/// decider si deux titres ou deux artistes designent la meme chose :
/// `DiscoveryService` (recherche Deezer, statut "dans la bibliotheque"),
/// `AlbumScreen`/`ArtistScreen` (fusion tracklist Deezer + NAS, grise/blanc),
/// et l'import CSV (`StreamingMatchScreen`).
///
/// Avant ce service, chacun de ces 4 endroits avait sa propre reimplementation
/// de la normalisation et du matching flou, et elles n'etaient pas d'accord
/// entre elles (ex: les accents n'etaient repliees que par l'import CSV) --
/// un meme titre pouvait donc etre reconnu "possede" sur un ecran et pas sur
/// un autre. Cette classe centralise l'algorithme le plus abouti (celui de
/// l'import CSV, teste en conditions reelles sur de vrais exports Spotify)
/// pour que le resultat soit identique partout.
class MatchingService {
  MatchingService._();

  static const Set<String> _stopWords = {
    'the', 'a', 'an', 'and', 'or', 'as', 'at', 'by', 'for', 'in', 'of', 'on',
    'to', 'with',
    'de', 'la', 'le', 'les', 'et', 'des', 'du', 'un', 'une', 'au', 'aux',
    'en', 'dans',
    'i', 'you', 'he', 'she', 'it', 'we', 'they', 'me', 'my', 'your', 'his',
    'her', 'its',
  };

  /// Noms qui apparaissent parfois comme "artiste principal" sur des
  /// compilations/BO alors qu'ils ne designent aucun artiste reel (label,
  /// distributeur, cast generique...). On privilegie le 2e nom de la liste
  /// quand celui-ci en fait partie.
  static const Set<String> _genericArtistNames = {
    'arcane',
    'league of legends',
    'glee cast',
    'k-pop demon hunters cast',
    'cast of epic: the musical',
    'teamfight tactics',
    'riot games',
    'fueled by ramen',
    'warner records',
    'universal music',
    'sony music',
    'atlantic records',
    'columbia',
    'epic',
    'interscope',
    'republic records',
  };

  // ── NORMALISATION ──

  /// Normalise pour comparaison : minuscule, sans accents, sans ponctuation,
  /// espaces uniques.
  ///
  /// `\w` (utilise avant) ne reconnait que [A-Za-z0-9_] en Dart, meme avec
  /// une regex "unicode" -- un nom comme "美波" (aucun caractere ASCII)
  /// finissait donc entierement remplace par des espaces puis vide apres
  /// trim(). Une chaine normalisee vide fait ensuite matcher N'IMPORTE QUEL
  /// artiste/titre dans artistFieldContains (`f.contains('')` vaut toujours
  /// true), d'ou des albums d'artistes sans rapport affiches sur la page
  /// d'un artiste au nom non-latin. `\p{L}`/`\p{N}` (proprietes Unicode,
  /// necessitent `unicode: true`) reconnaissent les lettres/chiffres de
  /// n'importe quelle langue, donc "美波" reste "美波" au lieu de "".
  static String normalize(String text) {
    if (text.isEmpty) return '';
    var t = removeDiacritics(text.toLowerCase());
    t = t.replaceAll(RegExp(r'[^\p{L}\p{N}_\s]', unicode: true), ' ');
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t;
  }

  static String removeStopWords(String text) {
    return text
        .split(' ')
        .where((w) => w.length > 2 && !_stopWords.contains(w))
        .join(' ');
  }

  /// Retire les featuring, parentheses, suffixes de version d'un titre de
  /// morceau ("Titre (feat. X)", "Titre - Remix", "Titre (2019 Remaster)"...).
  static String coreTitle(String title) {
    var t = title.toLowerCase().trim();
    t = t.replaceAll(
        RegExp(r'\s*\(\s*(feat\.?|ft\.?|with|prod\.?|presents?)\s+[^)]*\)',
            caseSensitive: false),
        '');
    t = t.replaceAll(
        RegExp(r'\s*\[\s*(feat\.?|ft\.?|with|prod\.?|presents?)\s+[^\]]*\]',
            caseSensitive: false),
        '');
    t = t.replaceAll(
        RegExp(
            r'\s*[-–]\s*(.+remix|remix|edit|version|radio\s*edit|radio\s*mix|live|acoustic|sped\s*up|slowed|reverb|instrumental|cover|demo|bonus\s*track|skit|intro|outro|interlude|theme|from\s+the\s+series\s+.*|from\s+the\s+.*soundtrack|from\s+the\s+.*motion\s*picture|original\s*score)\s*$',
            caseSensitive: false),
        '');
    t = t.replaceAll(
        RegExp(
            r'\s*\(\s*\d{4}\s*(remaster|re-master|version|edit|mix)?\s*\)\s*$',
            caseSensitive: false),
        '');
    t = t.replaceAll(
        RegExp(
            r'\s*\(\s*(.+remix|remix|edit|version|radio|live|acoustic|sped\s*up|slowed|reverb|instrumental|cover|demo|theme|from)\s*[^)]*\)\s*$',
            caseSensitive: false),
        '');
    t = t.replaceAll(
        RegExp(r'\s+(feat\.?|ft\.?)\s+.*$', caseSensitive: false), '');
    t = t.replaceAll(RegExp(r'\s*\[[^\]]*\]'), '');
    t = t.replaceAll(RegExp(r'\s*\([^)]*\)'), '');
    return normalize(t);
  }

  /// Retire les prefixes "Vol./Season/Part..." et les mots generiques de BO
  /// ("original", "soundtrack"...) d'un titre d'ALBUM (different d'un titre
  /// de morceau : les coffrets/BO ont leurs propres conventions de nommage).
  static String coreAlbumTitle(String title) {
    var core = title.toLowerCase();
    core = core.replaceAll(
        RegExp(
            r'^(vol\.?|volume|season|part|act|episode|ep)\s*\d*\s*[:\-–—]\s*'),
        '');
    core = core.replaceAll(RegExp(r'\(.*?\)'), '');
    core = core.replaceAll(
        RegExp(
            r'\b(original|soundtrack|score|music|from|the|series|animated|of|ost|motion|picture)\b'),
        '');
    return normalize(core);
  }

  /// Normalise un nom d'artiste : retire "the " au debut, ignore les noms
  /// "generiques" (labels, cast de BO) au profit du vrai artiste s'il y en a
  /// un second, garde uniquement l'artiste principal (separateurs ; & ,).
  static String coreArtist(String artist) {
    if (artist.isEmpty) return '';
    var a = artist.toLowerCase().trim();
    a = a.replaceAll(RegExp(r'^the\s+'), '');
    final parts =
        a.split(';').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return '';

    String primary = parts[0];
    if (_genericArtistNames.contains(primary) && parts.length > 1) {
      primary = parts[1];
    }

    a = primary.replaceAll(RegExp(r'[&+,/-]'), ' ');
    return normalize(a);
  }

  // ── SIMILARITE ──

  static double jaroWinkler(String s1, String s2) {
    if (s1 == s2) return 1.0;
    if (s1.isEmpty || s2.isEmpty) return 0.0;

    final len1 = s1.length, len2 = s2.length;
    final matchDistance = ((len1 > len2 ? len1 : len2) / 2).floor() - 1;

    final s1Matches = List.filled(len1, false);
    final s2Matches = List.filled(len2, false);

    int matches = 0;
    for (int i = 0; i < len1; i++) {
      final start = (i - matchDistance).clamp(0, len2 - 1);
      final end = (i + matchDistance + 1).clamp(0, len2);
      for (int j = start; j < end; j++) {
        if (s2Matches[j] || s1[i] != s2[j]) continue;
        s1Matches[i] = true;
        s2Matches[j] = true;
        matches++;
        break;
      }
    }

    if (matches == 0) return 0.0;

    int transpositions = 0, k = 0;
    for (int i = 0; i < len1; i++) {
      if (!s1Matches[i]) continue;
      while (!s2Matches[k]) {
        k++;
      }
      if (s1[i] != s2[k]) transpositions++;
      k++;
    }

    final jaro = ((matches / len1) +
            (matches / len2) +
            ((matches - transpositions / 2.0) / matches)) /
        3.0;

    int prefix = 0;
    for (int i = 0; i < (len1 < len2 ? len1 : len2); i++) {
      if (s1[i] == s2[i]) {
        prefix++;
      } else {
        break;
      }
      if (prefix >= 4) break;
    }

    return jaro + (prefix * 0.1 * (1 - jaro));
  }

  static int _levenshtein(String a, String b) {
    final matrix = List.generate(
      a.length + 1,
      (i) => List.filled(b.length + 1, 0),
    );
    for (var i = 0; i <= a.length; i++) {
      matrix[i][0] = i;
    }
    for (var j = 0; j <= b.length; j++) {
      matrix[0][j] = j;
    }
    for (var i = 1; i <= a.length; i++) {
      for (var j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        matrix[i][j] = [
          matrix[i - 1][j] + 1,
          matrix[i][j - 1] + 1,
          matrix[i - 1][j - 1] + cost,
        ].reduce((x, y) => x < y ? x : y);
      }
    }
    return matrix[a.length][b.length];
  }

  /// Similarite normalisee (0-1) basee sur la distance de Levenshtein.
  static double similarity(String a, String b) {
    if (a.isEmpty || b.isEmpty) return 0;
    if (a == b) return 1.0;
    final dist = _levenshtein(a, b);
    final maxLen = a.length > b.length ? a.length : b.length;
    return 1.0 - (dist / maxLen);
  }

  // ── MATCHING ──

  /// Deux titres de MORCEAU designent-ils le meme enregistrement ?
  /// Pas de raccourci par contains() direct : "Around the World" est un
  /// prefixe litteral de "Around the World Radio Edit"/"...Motorbass Vice
  /// Mix" une fois normalise, alors que ce sont des enregistrements
  /// differents. La similarite Jaro-Winkler est sensible a la longueur : un
  /// titre nettement plus long a cause d'un suffixe de version tombe
  /// naturellement sous le seuil (garde-fou anti-prefixe en plus).
  static bool titlesMatch(String rawA, String rawB) {
    final a = coreTitle(rawA);
    final b = coreTitle(rawB);
    if (a.isEmpty || b.isEmpty) return false;
    if (a == b) return true;

    final cleanA = removeStopWords(a);
    final cleanB = removeStopWords(b);
    if (cleanA.isEmpty || cleanB.isEmpty) return false;
    if (jaroWinkler(cleanA, cleanB) <= 0.95) return false;

    final shorter = a.length < b.length ? a : b;
    final longer = a.length < b.length ? b : a;
    if (longer.contains(shorter) && shorter.length < longer.length * 0.8) {
      return false;
    }
    return true;
  }

  /// Deux titres d'ALBUM designent-ils le meme album ?
  static bool albumsMatch(String rawA, String rawB) {
    final a = normalize(rawA);
    final b = normalize(rawB);
    if (a.isEmpty || b.isEmpty) return false;
    if (a == b) return true;
    if (a.contains(b) || b.contains(a)) return true;

    final coreA = coreAlbumTitle(a);
    final coreB = coreAlbumTitle(b);
    if (coreA.isEmpty || coreB.isEmpty) return false;
    if (coreA == coreB) return true;
    if (coreA.contains(coreB) || coreB.contains(coreA)) return true;

    // coreA/coreB (pas a/b) : deux titres courts commencant tous les deux
    // par un mot generique ("The Crux" / "The Call") restaient similaires a
    // plus de 50% sur les chaines completes rien qu'a cause du prefixe
    // partage, ce qui fusionnait des singles sans rapport dans le mauvais
    // album (retour utilisateur). Comparer les titres deja debarrasses de
    // ces mots generiques evite ce faux positif.
    return similarity(coreA, coreB) > 0.50;
  }

  /// Deux champs artiste designent-ils le meme artiste principal ?
  /// [strict] exige un recouvrement de mots plus eleve (70% au lieu de 50%) --
  /// a utiliser quand le titre a deja matche et qu'on veut eviter un faux
  /// positif sur l'artiste (ex: deux artistes differents avec un prenom
  /// commun).
  static bool artistsMatch(String rawA, String rawB, {bool strict = false}) {
    final a = coreArtist(rawA);
    final b = coreArtist(rawB);
    if (a.isEmpty || b.isEmpty) return false;
    if (a == b) return true;

    // minLen >= 2 laissait passer un artiste "June" des qu'il apparaissait
    // comme sous-chaine de n'importe quel autre nom ("Jace June", "Cloudy
    // June"...) -- un mot court et courant ne prouve rien a lui seul. On
    // n'accepte la simple inclusion que si le nom inclus est assez long
    // pour ne pas etre juste un mot generique partage (retour utilisateur :
    // page artiste "Jace June" recuperant les titres de "June"). Le cas
    // legitime ("Daft Punk" dans le champ multi-artiste "Daft Punk/Pharrell
    // Williams") reste couvert, "Daft Punk" etant bien plus long que 6.
    final shorter = a.length < b.length ? a : b;
    final longer = a.length < b.length ? b : a;
    if (longer.contains(shorter) && shorter.length >= 6) return true;

    final minWordLen = strict ? 1 : 2;
    final aWords = a.split(' ').where((w) => w.length > minWordLen).toSet();
    final bWords = b.split(' ').where((w) => w.length > minWordLen).toSet();
    // Recouvrement de mots seulement si les deux noms en ont reellement
    // plusieurs -- sinon un artiste au nom d'un seul mot ("June") atteint
    // toujours 100% de recouvrement avec lui-meme des qu'il apparait dans
    // l'autre nom, meme si le reste du nom ("Jace"/"Cloudy") n'a rien a voir.
    if (aWords.length < 2 || bWords.length < 2) return false;
    final common = aWords.intersection(bWords);
    // >= 2 mots communs obligatoire (pas juste une alternative en mode non
    // strict comme avant) : "Cloudy June" et "Jace June" ont chacun 2 mots
    // et un seul en commun ("june"), ce qui atteignait deja 50% du plus
    // court -- un seul mot partage, aussi frequent que "June", ne suffit
    // pas a conclure que c'est le meme artiste. Un vrai doublon ("arctic
    // monkeys tour" / "arctic monkeys revival") partage lui au moins 2 mots.
    if (common.length < 2) return false;

    final threshold = strict ? 0.7 : 0.5;
    return common.length >= aWords.length * threshold ||
        common.length >= bWords.length * threshold;
  }

  /// Le champ artiste brut d'une piste NAS (ex: "Daft Punk/Pharrell
  /// Williams") contient-il l'artiste recherche, en tant que principal ou en
  /// featuring ?
  static bool artistFieldContains(String? artistField, String search) {
    if (artistField == null || artistField.isEmpty || search.isEmpty) {
      return false;
    }
    final s = normalize(search);
    final f = normalize(artistField);
    // s vide (ex: nom compose uniquement de symboles) : f.contains('') vaut
    // toujours true en Dart, ce qui matcherait n'importe quel artiste --
    // voir le commentaire de normalize() pour le cas qui declenchait ca.
    if (s.isEmpty) return false;
    if (f == s) return true;
    // s.length >= 6 : meme garde-fou que le contains-shortcut d'artistsMatch
    // -- un terme cherche court ("June") ne doit pas matcher des qu'il
    // apparait comme simple sous-chaine d'un champ plus long ("Jace June"),
    // seul un vrai nom "en entier" dans le champ (ex: "David Bowie" dans
    // "Queen/David Bowie") est un signal fiable.
    if (s.length >= 6 && f.contains(s)) return true;
    if (f.split(RegExp(r'[/&,]')).any((p) => p.trim() == s)) return true;
    return artistsMatch(artistField, search);
  }
}
