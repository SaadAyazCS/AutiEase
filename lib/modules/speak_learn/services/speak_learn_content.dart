import '../../../models/app_models.dart';
import '../../../repositories/app_repositories.dart';
import '../models/speak_learn_item.dart';
import '../models/speak_learn_level_kind.dart';

/// Curated and Firestore-backed content for Speak & Learn (isolated from old game screens).
class SpeakLearnContent {
  SpeakLearnContent._();

  static const List<String> alphabetLetters = [
    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M',
    'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
  ];

  static List<SpeakLearnItem> alphabetItems() {
    return [
      for (final letter in alphabetLetters)
        SpeakLearnItem(
          id: 'letter-$letter',
          displayText: letter,
          speakText: letter,
        ),
    ];
  }

  /// Words from the assigned module's [LearningModuleModel.assetRefs], same resolution idea as Learning Games.
  static Future<List<SpeakLearnItem>> loadWordItems(LearningModuleModel? module) async {
    if (module == null) {
      return _defaultWords();
    }
    final allItems = await AppRepositories.content.getAllContentItems();
    final scoped = _resolveModuleItems(module: module, allItems: allItems);
    if (scoped.isEmpty) {
      return _defaultWords();
    }
    scoped.sort((a, b) => a.title.compareTo(b.title));
    return scoped
        .map(
          (item) => SpeakLearnItem(
            id: item.id,
            displayText: item.title,
            speakText: item.audioText.trim().isEmpty ? item.title : item.audioText,
            imageUrl: item.imageUrl.isEmpty ? null : item.imageUrl,
            iconEmoji: _emojiForWord(item.title),
          ),
        )
        .toList();
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
      'I want water',
      'I am happy',
      'I need help',
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
          tag: 'REQUESTS',
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

  static List<SpeakLearnItem> _defaultWords() {
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
    final cleaned = raw.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
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
          final s = '${_normalizeKey(m.gameTypeKey)} ${_normalizeKey(m.id)} ${_normalizeKey(m.title)}';
          return s.contains('alphabet');
        });
      case SpeakLearnLevelKind.words:
        return pick((m) {
          final s = '${_normalizeKey(m.gameTypeKey)} ${_normalizeKey(m.id)} ${_normalizeKey(m.title)}';
          return s.contains('word') && !s.contains('sentence');
        });
      case SpeakLearnLevelKind.sentences:
        return pick((m) {
          final s = '${_normalizeKey(m.gameTypeKey)} ${_normalizeKey(m.id)} ${_normalizeKey(m.title)}';
          return s.contains('sentence');
        });
    }
  }
}
