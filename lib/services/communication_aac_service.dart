import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../config/communication_figma_catalog.dart';
import '../repositories/app_repositories.dart';

class CommunicationAacSentence {
  const CommunicationAacSentence({
    required this.id,
    required this.text,
    required this.icon,
    required this.isDefault,
    required this.isPinned,
    required this.usageCount,
    required this.sortOrder,
  });

  final String id;
  final String text;
  final String icon;
  final bool isDefault;
  final bool isPinned;
  final int usageCount;
  final int sortOrder;

  CommunicationAacSentence copyWith({
    String? text,
    String? icon,
    bool? isPinned,
    int? usageCount,
    int? sortOrder,
  }) {
    return CommunicationAacSentence(
      id: id,
      text: text ?? this.text,
      icon: icon ?? this.icon,
      isDefault: isDefault,
      isPinned: isPinned ?? this.isPinned,
      usageCount: usageCount ?? this.usageCount,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }
}

class CommunicationAacItemState {
  const CommunicationAacItemState({
    required this.childId,
    required this.categoryId,
    required this.categoryName,
    required this.itemId,
    required this.itemName,
    required this.sentences,
  });

  final String childId;
  final String categoryId;
  final String categoryName;
  final String itemId;
  final String itemName;
  final List<CommunicationAacSentence> sentences;

  List<CommunicationAacSentence> get displaySentences {
    final sorted = List<CommunicationAacSentence>.from(sentences);
    sorted.sort((a, b) {
      if (a.isPinned != b.isPinned) {
        return a.isPinned ? -1 : 1;
      }
      if (a.usageCount != b.usageCount) {
        return b.usageCount.compareTo(a.usageCount);
      }
      return a.sortOrder.compareTo(b.sortOrder);
    });
    return sorted;
  }

  List<CommunicationAacSentence> get frequentSentences {
    final used = sentences
        .where((sentence) => sentence.usageCount > 0)
        .toList();
    used.sort((a, b) => b.usageCount.compareTo(a.usageCount));
    return used.take(3).toList();
  }

  CommunicationAacItemState incrementUsage(String sentenceId) {
    return CommunicationAacItemState(
      childId: childId,
      categoryId: categoryId,
      categoryName: categoryName,
      itemId: itemId,
      itemName: itemName,
      sentences: sentences
          .map(
            (sentence) => sentence.id == sentenceId
                ? sentence.copyWith(usageCount: sentence.usageCount + 1)
                : sentence,
          )
          .toList(growable: false),
    );
  }
}

class CommunicationAacService {
  const CommunicationAacService();

  static const maxSentencesPerItem = 10;
  static const maxCustomSentencesPerItem = 5;
  static const maxSentenceTextLength = 150;

  CollectionReference<Map<String, dynamic>> get _collection => AppRepositories
      .firestore
      .collection(FirestoreCollections.communicationSentenceSettings);

  Future<CommunicationAacItemState> loadItemState({
    required String childId,
    required CommunicationBoardDefinition board,
    required CommunicationBoardItem item,
  }) async {
    final ref = _docRef(childId: childId, boardId: board.id, itemId: item.id);
    final templates = _defaultTemplates(board: board, item: item);
    final fallback = _fallbackState(
      childId: childId,
      board: board,
      item: item,
      templates: templates,
    );

    final DocumentSnapshot<Map<String, dynamic>> snapshot;
    try {
      snapshot = await ref.get();
    } on FirebaseException catch (error) {
      debugPrint('Unable to load AAC sentence settings: ${error.code}');
      return fallback;
    } catch (error) {
      debugPrint('Unable to load AAC sentence settings: $error');
      return fallback;
    }

    final data = snapshot.data() ?? const <String, dynamic>{};
    final hiddenDefaultIds = _stringList(data['hiddenDefaultSentenceIds']);
    final overrides = _stringMap(data['defaultSentenceOverrides']);
    final pinnedIds = _stringList(data['favoriteSentences']).toSet();
    final usageCount = _intMap(data['usageCount']);
    final order = _stringList(data['sentenceOrder']);
    final custom = _customSentences(data['customSentences']);

    final sentences = <CommunicationAacSentence>[];
    for (var i = 0; i < templates.length; i++) {
      final template = templates[i];
      if (hiddenDefaultIds.contains(template.id)) {
        continue;
      }
      sentences.add(
        CommunicationAacSentence(
          id: template.id,
          text: overrides[template.id] ?? template.text,
          icon: template.icon,
          isDefault: true,
          isPinned: pinnedIds.contains(template.id),
          usageCount: usageCount[template.id] ?? 0,
          sortOrder: _orderFor(template.id, order, fallback: i),
        ),
      );
    }

    for (final customSentence in custom) {
      final id = customSentence.id;
      sentences.add(
        customSentence.copyWith(
          isPinned: pinnedIds.contains(id) || customSentence.isPinned,
          usageCount: usageCount[id] ?? customSentence.usageCount,
          sortOrder: _orderFor(id, order, fallback: customSentence.sortOrder),
        ),
      );
    }

    sentences.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    if (!snapshot.exists) {
      try {
        await ref.set({
          'childId': childId,
          'categoryId': board.id,
          'category': board.title,
          'itemId': item.id,
          'item': item.label,
          'defaultSentences': templates.map((e) => e.text).toList(),
          'customSentences': const <Map<String, dynamic>>[],
          'favoriteSentences': const <String>[],
          'usageCount': const <String, int>{},
          'sentenceOrder': sentences.map((e) => e.id).toList(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } on FirebaseException catch (error) {
        debugPrint('Unable to initialize AAC sentence settings: ${error.code}');
      } catch (error) {
        debugPrint('Unable to initialize AAC sentence settings: $error');
      }
    }

    return CommunicationAacItemState(
      childId: childId,
      categoryId: board.id,
      categoryName: board.title,
      itemId: item.id,
      itemName: item.label,
      sentences: sentences,
    );
  }

  Future<void> saveItemState({
    required String childId,
    required CommunicationBoardDefinition board,
    required CommunicationBoardItem item,
    required List<CommunicationAacSentence> sentences,
  }) async {
    final templates = _defaultTemplates(board: board, item: item);
    final defaultById = {
      for (final template in templates) template.id: template,
    };
    final defaultIdsInDraft = sentences
        .where((sentence) => defaultById.containsKey(sentence.id))
        .map((sentence) => sentence.id)
        .toSet();
    final hiddenDefaultIds = defaultById.keys
        .where((id) => !defaultIdsInDraft.contains(id))
        .toList();
    final overrides = <String, String>{};
    final pinnedIds = <String>[];
    final custom = <Map<String, dynamic>>[];

    for (var i = 0; i < sentences.length; i++) {
      final sentence = sentences[i];
      final defaultTemplate = defaultById[sentence.id];
      if (sentence.isPinned) {
        pinnedIds.add(sentence.id);
      }
      if (defaultTemplate != null) {
        if (sentence.text.trim() != defaultTemplate.text) {
          overrides[sentence.id] = sentence.text.trim();
        }
        continue;
      }
      custom.add({
        'id': sentence.id,
        'text': sentence.text.trim(),
        'icon': sentence.icon,
        'sortOrder': i,
        'pinned': sentence.isPinned,
      });
    }

    await _docRef(childId: childId, boardId: board.id, itemId: item.id).set({
      'childId': childId,
      'categoryId': board.id,
      'category': board.title,
      'itemId': item.id,
      'item': item.label,
      'defaultSentences': templates.map((e) => e.text).toList(),
      'customSentences': custom.take(maxCustomSentencesPerItem).toList(),
      'defaultSentenceOverrides': overrides,
      'hiddenDefaultSentenceIds': hiddenDefaultIds,
      'favoriteSentences': pinnedIds,
      'sentenceOrder': sentences.map((e) => e.id).toList(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  CommunicationAacItemState defaultItemState({
    required String childId,
    required CommunicationBoardDefinition board,
    required CommunicationBoardItem item,
  }) {
    return _fallbackState(
      childId: childId,
      board: board,
      item: item,
      templates: _defaultTemplates(board: board, item: item),
    );
  }

  Future<void> recordSentenceUse({
    required String childId,
    required CommunicationBoardDefinition board,
    required CommunicationBoardItem item,
    required CommunicationAacSentence sentence,
  }) async {
    await _docRef(childId: childId, boardId: board.id, itemId: item.id).set({
      'childId': childId,
      'categoryId': board.id,
      'category': board.title,
      'itemId': item.id,
      'item': item.label,
      'usageCount.${sentence.id}': FieldValue.increment(1),
      'lastUsedSentence': sentence.text,
      'lastUsedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  DocumentReference<Map<String, dynamic>> _docRef({
    required String childId,
    required String boardId,
    required String itemId,
  }) {
    return _collection
        .doc(childId)
        .collection('items')
        .doc('${boardId}_$itemId');
  }

  CommunicationAacItemState _fallbackState({
    required String childId,
    required CommunicationBoardDefinition board,
    required CommunicationBoardItem item,
    required List<_SentenceTemplate> templates,
  }) {
    return CommunicationAacItemState(
      childId: childId,
      categoryId: board.id,
      categoryName: board.title,
      itemId: item.id,
      itemName: item.label,
      sentences: [
        for (var i = 0; i < templates.length; i++)
          CommunicationAacSentence(
            id: templates[i].id,
            text: templates[i].text,
            icon: templates[i].icon,
            isDefault: true,
            isPinned: false,
            usageCount: 0,
            sortOrder: i,
          ),
      ],
    );
  }

  int _orderFor(String id, List<String> order, {required int fallback}) {
    final index = order.indexOf(id);
    return index < 0 ? fallback + 100 : index;
  }

  List<CommunicationAacSentence> _customSentences(Object? value) {
    if (value is! Iterable) {
      return const <CommunicationAacSentence>[];
    }
    final out = <CommunicationAacSentence>[];
    var fallbackOrder = 100;
    for (final raw in value) {
      if (raw is! Map) {
        continue;
      }
      final text = raw['text']?.toString().trim() ?? '';
      if (text.isEmpty) {
        continue;
      }
      final id = raw['id']?.toString().trim().isNotEmpty == true
          ? raw['id'].toString()
          : 'custom-${DateTime.now().microsecondsSinceEpoch}-${out.length}';
      out.add(
        CommunicationAacSentence(
          id: id,
          text: text,
          icon: raw['icon']?.toString().trim().isNotEmpty == true
              ? raw['icon'].toString()
              : '\u{1F4AC}',
          isDefault: false,
          isPinned: raw['pinned'] == true,
          usageCount: _asInt(raw['usageCount']),
          sortOrder: _asInt(raw['sortOrder'], fallback: fallbackOrder++),
        ),
      );
    }
    return out.take(maxCustomSentencesPerItem).toList();
  }

  List<_SentenceTemplate> _defaultTemplates({
    required CommunicationBoardDefinition board,
    required CommunicationBoardItem item,
  }) {
    final label = item.label.trim();
    final lower = label.toLowerCase();
    final icon = _sentenceIcon(board: board, item: item);
    final plural = _plural(lower);
    final foodPhrase = _foodPhrase(lower);
    final sentences = switch (board.id) {
      'colors' => <String>[
        'I like $lower.',
        '${_title(label)} is pretty.',
        'I want the $lower one.',
        "I don't like $lower.",
        '${_title(label)} looks nice.',
      ],
      'animals' => <String>[
        'I like $plural.',
        'The $lower is cute.',
        'I want to pet the $lower.',
        'I see the $lower.',
        'The $lower is here.',
      ],
      'food' => <String>[
        'I want $foodPhrase.',
        '${_title(label)} tastes good.',
        'I am hungry.',
        'Can I have $lower?',
        "I don't want $lower.",
      ],
      'emotions' || 'feelings' => <String>[
        'I feel $lower.',
        'I am $lower.',
        'I need help.',
        'I want a break.',
        'Please listen to me.',
      ],
      'emergency' => <String>[
        item.speakText,
        'Please help me.',
        'I need this now.',
        'Please stop.',
        'I want to tell you something.',
      ],
      'family' => <String>[
        'I want my $lower.',
        'Where is my $lower?',
        'I love my $lower.',
        'Please call my $lower.',
        'I want to talk to my $lower.',
      ],
      'clothes' => <String>[
        'I want my $lower.',
        'I need my $lower.',
        'This $lower feels good.',
        'I do not want this $lower.',
        'Please help me wear my $lower.',
      ],
      'shapes' => <String>[
        'I see a $lower.',
        'I like the $lower.',
        'I want the $lower.',
        'The $lower is nice.',
        'Show me the $lower.',
      ],
      'numbers' => <String>[
        'I choose ${item.speakText.toLowerCase()}.',
        'I want ${item.speakText.toLowerCase()}.',
        'Show me ${item.speakText.toLowerCase()}.',
        'I see ${item.speakText.toLowerCase()}.',
        'This is ${item.speakText.toLowerCase()}.',
      ],
      'alphabets' => <String>[
        'I choose ${item.speakText}.',
        'This is ${item.speakText}.',
        'Show me ${item.speakText}.',
        'I see ${item.speakText}.',
        'I want ${item.speakText}.',
      ],
      _ => <String>[
        'I want $lower.',
        'I like $lower.',
        'I need $lower.',
        "I don't want $lower.",
        'Please show me $lower.',
      ],
    };

    return List<_SentenceTemplate>.generate(
      sentences.length,
      (index) => _SentenceTemplate(
        id: '${item.id}-default-$index',
        text: sentences[index],
        icon: icon,
      ),
      growable: false,
    );
  }

  String _sentenceIcon({
    required CommunicationBoardDefinition board,
    required CommunicationBoardItem item,
  }) {
    if (item.emoji != null && item.emoji!.trim().isNotEmpty) {
      return item.emoji!;
    }
    return switch (board.id) {
      'colors' => '\u{1F3A8}',
      'food' => '\u{1F34E}',
      'emotions' || 'feelings' => '\u{1F642}',
      'emergency' => '\u{1F6A8}',
      'family' => '\u{1F46A}',
      'clothes' => '\u{1F455}',
      'shapes' => '\u{1F536}',
      'numbers' => '\u{1F522}',
      'alphabets' => '\u{1F524}',
      _ => '\u{1F4AC}',
    };
  }

  String _title(String value) {
    if (value.isEmpty) {
      return value;
    }
    return value[0].toUpperCase() + value.substring(1);
  }

  String _plural(String value) {
    if (value.endsWith('s')) {
      return value;
    }
    if (value.endsWith('y')) {
      return '${value.substring(0, value.length - 1)}ies';
    }
    return '${value}s';
  }

  String _foodPhrase(String value) {
    if (value.endsWith('s')) {
      return value;
    }
    final first = value.isEmpty ? '' : value[0];
    final article = 'aeiou'.contains(first) ? 'an' : 'a';
    return '$article $value';
  }

  List<String> _stringList(Object? value) {
    if (value is Iterable) {
      return value.map((entry) => entry.toString()).toList();
    }
    return const <String>[];
  }

  Map<String, String> _stringMap(Object? value) {
    if (value is Map) {
      return value.map(
        (key, entry) => MapEntry(key.toString(), entry.toString()),
      );
    }
    return const <String, String>{};
  }

  Map<String, int> _intMap(Object? value) {
    if (value is Map) {
      return value.map((key, entry) => MapEntry(key.toString(), _asInt(entry)));
    }
    return const <String, int>{};
  }

  int _asInt(Object? value, {int fallback = 0}) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }
}

class _SentenceTemplate {
  const _SentenceTemplate({
    required this.id,
    required this.text,
    required this.icon,
  });

  final String id;
  final String text;
  final String icon;
}
