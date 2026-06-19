/// Practice levels inside the standalone Speak & Learn module.
enum SpeakLearnLevelKind {
  alphabets,
  words,
  sentences,
}

extension SpeakLearnLevelKindX on SpeakLearnLevelKind {
  String get uiTitle => switch (this) {
        SpeakLearnLevelKind.alphabets => 'Alphabets Practice',
        SpeakLearnLevelKind.words => 'Word Practice',
        SpeakLearnLevelKind.sentences => 'Sentence Practice',
      };

  String get levelsCardLabel => switch (this) {
        SpeakLearnLevelKind.alphabets => 'Alphabets',
        SpeakLearnLevelKind.words => 'Words',
        SpeakLearnLevelKind.sentences => 'Sentences',
      };

  /// Displayed under the main title on the practice screen (design: Level 1/2/3).
  String get levelSubtitle => switch (this) {
        SpeakLearnLevelKind.alphabets => 'Level 1',
        SpeakLearnLevelKind.words => 'Level 2',
        SpeakLearnLevelKind.sentences => 'Level 3',
      };

  int get levelNumber => switch (this) {
        SpeakLearnLevelKind.alphabets => 1,
        SpeakLearnLevelKind.words => 2,
        SpeakLearnLevelKind.sentences => 3,
      };

  /// Badge stored in analytics metadata.
  String get badgeKey => switch (this) {
        SpeakLearnLevelKind.alphabets => 'bronze',
        SpeakLearnLevelKind.words => 'silver',
        SpeakLearnLevelKind.sentences => 'gold',
      };
}
