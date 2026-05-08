import '../../../models/app_models.dart';
import '../../../repositories/app_repositories.dart';
import '../models/speak_learn_item.dart';
import '../models/speak_learn_level_kind.dart';

/// Curated and Firestore-backed content for Speak & Learn (isolated from old game screens).
class SpeakLearnContent {
  SpeakLearnContent._();

  static const List<String> alphabetLetters = [
    'A',
    'B',
    'C',
    'D',
    'E',
    'F',
    'G',
    'H',
    'I',
    'J',
    'K',
    'L',
    'M',
    'N',
    'O',
    'P',
    'Q',
    'R',
    'S',
    'T',
    'U',
    'V',
    'W',
    'X',
    'Y',
    'Z',
  ];

  static List<SpeakLearnItem> alphabetItems() {
    return [
      for (final letter in alphabetLetters)
        SpeakLearnItem(
          id: 'letter-$letter',
          displayText:
              '$letter ${_soundForLetter(letter)} ${_exampleForLetter(letter)}',
          speakText: letter,
          phoneticSound: _soundForLetter(letter),
          exampleWord: _exampleForLetter(letter),
          matchText: letter.toLowerCase(),
        ),
    ];
  }

  /// Words from the assigned module's [LearningModuleModel.assetRefs], same resolution idea as Learning Games.
  static Future<List<SpeakLearnItem>> loadWordItems(
    LearningModuleModel? module,
  ) async {
    if (module == null) {
      return _defaultWords();
    }
    final allItems = await AppRepositories.content.getAllContentItems();
    final scoped = _resolveModuleItems(module: module, allItems: allItems);
    if (scoped.isEmpty) {
      return _defaultWords();
    }
    scoped.sort((a, b) => a.title.compareTo(b.title));
    final moduleItems = scoped
        .map(
          (item) => SpeakLearnItem(
            id: item.id,
            displayText: item.title,
            speakText: item.audioText.trim().isEmpty
                ? item.title
                : item.audioText,
            imageUrl: item.imageUrl.isEmpty ? null : item.imageUrl,
            iconEmoji: _emojiForWord(item.title),
          ),
        )
        .toList();
    final seen = moduleItems
        .map((item) => item.displayText.toLowerCase())
        .toSet();
    return [
      ..._functionalWords().where(
        (item) => seen.add(item.displayText.toLowerCase()),
      ),
      ...moduleItems,
    ];
  }

  /// Builds short sentences from feelings/emotions content and a few fixed useful phrases.
  static Future<List<SpeakLearnItem>> loadSentenceItems(
    LearningModuleModel? module,
  ) async {
    final allItems = await AppRepositories.content.getAllContentItems();
    final scoped = module != null
        ? _resolveModuleItems(module: module, allItems: allItems)
        : <ContentItem>[];
    final out = <SpeakLearnItem>[];

    final templates = <String>[
      'I need help',
      'I want water',
      'Please stop',
      'I feel sad',
      'I am happy',
      'I feel okay',
      'I like this',
    ];

    var i = 0;
    for (final line in templates) {
      out.add(
        SpeakLearnItem(
          id: 'sentence-fixed-$i',
          displayText: line,
          speakText: line,
          tag: _tagForFixedSentence(line),
        ),
      );
      i++;
    }

    for (final item in scoped) {
      final t = item.title.trim();
      if (t.isEmpty) {
        continue;
      }
      final lower = t.toLowerCase();
      final sentence = 'I feel $lower';
      out.add(
        SpeakLearnItem(
          id: 'sentence-${item.id}',
          displayText: sentence,
          speakText: sentence,
          tag: 'FEELINGS',
        ),
      );
    }

    if (out.length < 6) {
      out.addAll(_fallbackSentences());
    }

    // De-dupe by display text
    final seen = <String>{};
    return out.where((e) => seen.add(e.displayText.toLowerCase())).toList();
  }

  static List<SpeakLearnItem> _fallbackSentences() {
    return const [
      SpeakLearnItem(
        id: 'fb-s1',
        displayText: 'I want food',
        speakText: 'I want food',
        tag: 'REQUESTS',
      ),
      SpeakLearnItem(
        id: 'fb-s2',
        displayText: 'I feel sad',
        speakText: 'I feel sad',
        tag: 'FEELINGS',
      ),
    ];
  }

  static String _tagForFixedSentence(String sentence) {
    return switch (sentence.toLowerCase()) {
      'i feel sad' ||
      'i am happy' ||
      'i feel okay' ||
      'i like this' => 'FEELINGS',
      _ => 'REQUESTS',
    };
  }

  static List<SpeakLearnItem> _defaultWords() {
    return _functionalWords();
  }

  // ignore: unused_element
  static List<SpeakLearnItem> _legacyDefaultWords() {
    return const [
      SpeakLearnItem(
        id: 'w-water',
        displayText: 'Water',
        speakText: 'Water',
        iconEmoji: '💧',
      ),
      SpeakLearnItem(
        id: 'w-happy',
        displayText: 'Happy',
        speakText: 'Happy',
        iconEmoji: '😊',
      ),
      SpeakLearnItem(
        id: 'w-mom',
        displayText: 'Mom',
        speakText: 'Mom',
        iconEmoji: '👩',
      ),
      SpeakLearnItem(
        id: 'w-dad',
        displayText: 'Dad',
        speakText: 'Dad',
        iconEmoji: '👨',
      ),
    ];
  }

  static List<SpeakLearnItem> _functionalWords() {
    return const [
      SpeakLearnItem(id: 'w-water', displayText: 'Water', speakText: 'Water'),
      SpeakLearnItem(id: 'w-help', displayText: 'Help', speakText: 'Help'),
      SpeakLearnItem(
        id: 'w-bathroom',
        displayText: 'Bathroom',
        speakText: 'Bathroom',
      ),
      SpeakLearnItem(
        id: 'w-hungry',
        displayText: 'Hungry',
        speakText: 'Hungry',
      ),
      SpeakLearnItem(id: 'w-stop', displayText: 'Stop', speakText: 'Stop'),
      SpeakLearnItem(id: 'w-more', displayText: 'More', speakText: 'More'),
      SpeakLearnItem(id: 'w-yes', displayText: 'Yes', speakText: 'Yes'),
      SpeakLearnItem(id: 'w-no', displayText: 'No', speakText: 'No'),
      SpeakLearnItem(id: 'w-pain', displayText: 'Pain', speakText: 'Pain'),
    ];
  }

  static String _soundForLetter(String letter) {
    return switch (letter) {
      'A' => '/a/',
      'B' => '/b/',
      'C' => '/c/',
      'D' => '/d/',
      'E' => '/e/',
      'F' => '/f/',
      'G' => '/g/',
      'H' => '/h/',
      'I' => '/i/',
      'J' => '/j/',
      'K' => '/k/',
      'L' => '/l/',
      'M' => '/m/',
      'N' => '/n/',
      'O' => '/o/',
      'P' => '/p/',
      'Q' => '/q/',
      'R' => '/r/',
      'S' => '/s/',
      'T' => '/t/',
      'U' => '/u/',
      'V' => '/v/',
      'W' => '/w/',
      'X' => '/x/',
      'Y' => '/y/',
      'Z' => '/z/',
      _ => '/${letter.toLowerCase()}/',
    };
  }

  static String _exampleForLetter(String letter) {
    return switch (letter) {
      'A' => 'Apple',
      'B' => 'Ball',
      'C' => 'Cat',
      'D' => 'Dog',
      'E' => 'Egg',
      'F' => 'Fish',
      'G' => 'Grapes',
      'H' => 'Hat',
      'I' => 'Ice',
      'J' => 'Juice',
      'K' => 'Kite',
      'L' => 'Lion',
      'M' => 'Moon',
      'N' => 'Nest',
      'O' => 'Orange',
      'P' => 'Peach',
      'Q' => 'Queen',
      'R' => 'Rocket',
      'S' => 'Sun',
      'T' => 'Tree',
      'U' => 'Umbrella',
      'V' => 'Van',
      'W' => 'Water',
      'X' => 'X-ray',
      'Y' => 'Yellow',
      'Z' => 'Zebra',
      _ => letter,
    };
  }

  static String? _emojiForWord(String title) {
    final t = title.toLowerCase();
    if (t.contains('water')) {
      return '💧';
    }
    if (t.contains('happy')) {
      return '😊';
    }
    if (t.contains('sad')) {
      return '😢';
    }
    return null;
  }

  static String _normalizeKey(String raw) {
    final cleaned = raw.trim().toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]+'),
      '_',
    );
    return cleaned
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  static List<ContentItem> _resolveModuleItems({
    required LearningModuleModel module,
    required List<ContentItem> allItems,
  }) {
    final rawRefs = module.assetRefs.map((ref) => ref.trim()).toList();
    final categoryIds = <String>{};
    final itemIds = <String>{};
    final keywords = <String>{};

    for (final ref in rawRefs) {
      if (ref.isEmpty) {
        continue;
      }
      final lowerRef = ref.toLowerCase();
      if (lowerRef.startsWith('category:')) {
        categoryIds.add(lowerRef.substring('category:'.length));
        continue;
      }
      if (lowerRef.startsWith('item:')) {
        itemIds.add(lowerRef.substring('item:'.length));
        continue;
      }
      keywords.add(lowerRef);
      categoryIds.add(lowerRef);
      itemIds.add(lowerRef);
    }

    var filtered = allItems.where((item) {
      final lowerId = item.id.toLowerCase();
      final lowerCategory = item.categoryId.toLowerCase();
      return categoryIds.contains(lowerCategory) || itemIds.contains(lowerId);
    }).toList();

    if (filtered.isEmpty && keywords.isNotEmpty) {
      filtered = allItems.where((item) {
        final haystack =
            '${item.title} ${item.subtitle} ${item.audioText} ${item.tags.join(' ')}'
                .toLowerCase();
        return keywords.any(haystack.contains);
      }).toList();
    }

    return filtered;
  }

  static LearningModuleModel? moduleForKind(
    List<LearningModuleModel> modules,
    SpeakLearnLevelKind kind,
  ) {
    if (modules.isEmpty) {
      return null;
    }
    LearningModuleModel? pick(bool Function(LearningModuleModel m) match) {
      for (final m in modules) {
        if (match(m)) {
          return m;
        }
      }
      return null;
    }

    switch (kind) {
      case SpeakLearnLevelKind.alphabets:
        return pick((m) {
          final s =
              '${_normalizeKey(m.gameTypeKey)} ${_normalizeKey(m.id)} ${_normalizeKey(m.title)}';
          return s.contains('alphabet');
        });
      case SpeakLearnLevelKind.words:
        return pick((m) {
          final s =
              '${_normalizeKey(m.gameTypeKey)} ${_normalizeKey(m.id)} ${_normalizeKey(m.title)}';
          return s.contains('word') && !s.contains('sentence');
        });
      case SpeakLearnLevelKind.sentences:
        return pick((m) {
          final s =
              '${_normalizeKey(m.gameTypeKey)} ${_normalizeKey(m.id)} ${_normalizeKey(m.title)}';
          return s.contains('sentence');
        });
    }
  }
}
