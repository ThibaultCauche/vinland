import 'package:flutter_test/flutter_test.dart';
import 'package:vinland/services/matching_service.dart';

void main() {
  group('normalize', () {
    test('replie les accents', () {
      expect(MatchingService.normalize('Café Del Mar'),
          MatchingService.normalize('Cafe Del Mar'));
    });
  });

  group('titlesMatch', () {
    test('reconnait le meme titre malgre un feat', () {
      expect(
        MatchingService.titlesMatch(
            'Blinding Lights', 'Blinding Lights (feat. Rosalia)'),
        isTrue,
      );
    });

    test('garde-fou anti-prefixe : un titre plus long et non lie ne matche pas',
        () {
      // Cas documente par le pass 5 de l'import CSV d'origine : "TAKE ME" ne
      // doit pas matcher "take me as i am" (chanson differente au titre plus
      // long), meme si "take me" en est litteralement un prefixe.
      expect(
        MatchingService.titlesMatch('Take Me', 'Take Me As I Am'),
        isFalse,
      );
    });

    test('titres franchement differents ne matchent pas', () {
      expect(
        MatchingService.titlesMatch('Bohemian Rhapsody', 'Hotel California'),
        isFalse,
      );
    });
  });

  group('artistsMatch', () {
    test('meme artiste, casse et accents differents', () {
      expect(MatchingService.artistsMatch('Beyoncé', 'beyonce'), isTrue);
    });

    test('reconnait un featuring dans un champ multi-artiste', () {
      expect(
        MatchingService.artistsMatch('Daft Punk/Pharrell Williams', 'Daft Punk'),
        isTrue,
      );
    });

    test('le mode strict est plus exigeant que le mode par defaut', () {
      // Ni l'un ni l'autre n'est un sous-ensemble litteral de l'autre : seul
      // le recouvrement de mots ("arctic", "monkeys") departage loose/strict.
      const a = 'arctic monkeys tour';
      const b = 'arctic monkeys revival';
      final loose = MatchingService.artistsMatch(a, b);
      final strict = MatchingService.artistsMatch(a, b, strict: true);
      expect(loose, isTrue);
      expect(strict, isFalse);
    });
  });

  group('albumsMatch', () {
    test('ignore un prefixe de volume/saison pour un coffret de BO', () {
      expect(
        MatchingService.albumsMatch(
            'Arcane Season 2 (Original Soundtrack)', 'Arcane Season 2'),
        isTrue,
      );
    });
  });

  group('artistFieldContains', () {
    test('trouve un artiste au milieu d\'un champ multi-artiste NAS', () {
      expect(
        MatchingService.artistFieldContains('Queen/David Bowie', 'David Bowie'),
        isTrue,
      );
    });

    test('renvoie faux pour un champ vide ou nul', () {
      expect(MatchingService.artistFieldContains(null, 'Queen'), isFalse);
      expect(MatchingService.artistFieldContains('', 'Queen'), isFalse);
    });
  });
}
