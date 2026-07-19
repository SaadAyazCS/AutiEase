import 'package:flutter/material.dart';

enum CommunicationBoardLayout { grid, colors, alphabets }

class CommunicationBoardItem {
  const CommunicationBoardItem({
    required this.id,
    required this.label,
    required this.speakText,
    this.emoji,
    this.swatchColor,
    this.symbol,
    this.symbolColor,
  });

  final String id;
  final String label;
  final String speakText;
  final String? emoji;
  final Color? swatchColor;
  final String? symbol;
  final Color? symbolColor;
}

class CommunicationBoardDefinition {
  const CommunicationBoardDefinition({
    required this.id,
    required this.title,
    required this.homeEmoji,
    required this.layout,
    required this.items,
  });

  final String id;
  final String title;
  final String homeEmoji;
  final CommunicationBoardLayout layout;
  final List<CommunicationBoardItem> items;
}

class CommunicationFigmaCatalog {
  static const List<String> homeBoardOrder = <String>[
    'colors',
    'numbers',
    'animals',
    'alphabets',
    'clothes',
  ];

  static const Set<String> hiddenBoardIds = <String>{};
  static const Set<String> hiddenBoardTitles = <String>{};

  static const List<CommunicationBoardDefinition> boards =
      <CommunicationBoardDefinition>[
        CommunicationBoardDefinition(
          id: 'colors',
          title: 'Colors',
          homeEmoji: '🎨',
          layout: CommunicationBoardLayout.colors,
          items: <CommunicationBoardItem>[
            CommunicationBoardItem(
              id: 'color-yellow',
              label: 'Yellow',
              speakText: 'Yellow',
              swatchColor: Color(0xFFEBDD2B),
            ),
            CommunicationBoardItem(
              id: 'color-red',
              label: 'Red',
              speakText: 'Red',
              swatchColor: Color(0xFFB43437),
            ),
            CommunicationBoardItem(
              id: 'color-blue',
              label: 'Blue',
              speakText: 'Blue',
              swatchColor: Color(0xFF5539C4),
            ),
            CommunicationBoardItem(
              id: 'color-green',
              label: 'Green',
              speakText: 'Green',
              swatchColor: Color(0xFF59BB5E),
            ),
            CommunicationBoardItem(
              id: 'color-black',
              label: 'Black',
              speakText: 'Black',
              swatchColor: Color(0xFF30323A),
            ),
            CommunicationBoardItem(
              id: 'color-pink',
              label: 'Pink',
              speakText: 'Pink',
              swatchColor: Color(0xFFD66CC2),
            ),
          ],
        ),
        CommunicationBoardDefinition(
          id: 'numbers',
          title: 'Numbers',
          homeEmoji: '🔢',
          layout: CommunicationBoardLayout.grid,
          items: <CommunicationBoardItem>[
            CommunicationBoardItem(
              id: 'num-1',
              label: 'One',
              speakText: 'One',
              emoji: '1️⃣',
            ),
            CommunicationBoardItem(
              id: 'num-2',
              label: 'Two',
              speakText: 'Two',
              emoji: '2️⃣',
            ),
            CommunicationBoardItem(
              id: 'num-3',
              label: 'Three',
              speakText: 'Three',
              emoji: '3️⃣',
            ),
            CommunicationBoardItem(
              id: 'num-4',
              label: 'Four',
              speakText: 'Four',
              emoji: '4️⃣',
            ),
            CommunicationBoardItem(
              id: 'num-5',
              label: 'Five',
              speakText: 'Five',
              emoji: '5️⃣',
            ),
            CommunicationBoardItem(
              id: 'num-6',
              label: 'Six',
              speakText: 'Six',
              emoji: '6️⃣',
            ),
            CommunicationBoardItem(
              id: 'num-7',
              label: 'Seven',
              speakText: 'Seven',
              emoji: '7️⃣',
            ),
            CommunicationBoardItem(
              id: 'num-8',
              label: 'Eight',
              speakText: 'Eight',
              emoji: '8️⃣',
            ),
            CommunicationBoardItem(
              id: 'num-9',
              label: 'Nine',
              speakText: 'Nine',
              emoji: '9️⃣',
            ),
            CommunicationBoardItem(
              id: 'num-10',
              label: 'Ten',
              speakText: 'Ten',
              emoji: '🔟',
            ),
          ],
        ),
        CommunicationBoardDefinition(
          id: 'animals',
          title: 'Animals',
          homeEmoji: '🦁',
          layout: CommunicationBoardLayout.grid,
          items: <CommunicationBoardItem>[
            CommunicationBoardItem(
              id: 'animal-elephant',
              label: 'Elephant',
              speakText: 'Elephant',
              emoji: '🐘',
            ),
            CommunicationBoardItem(
              id: 'animal-giraffe',
              label: 'Giraffe',
              speakText: 'Giraffe',
              emoji: '🦒',
            ),
            CommunicationBoardItem(
              id: 'animal-monkey',
              label: 'Monkey',
              speakText: 'Monkey',
              emoji: '🐒',
            ),
            CommunicationBoardItem(
              id: 'animal-tiger',
              label: 'Tiger',
              speakText: 'Tiger',
              emoji: '🐅',
            ),
            CommunicationBoardItem(
              id: 'animal-bear',
              label: 'Bear',
              speakText: 'Bear',
              emoji: '🐻',
            ),
            CommunicationBoardItem(
              id: 'animal-duck',
              label: 'Duck',
              speakText: 'Duck',
              emoji: '🦆',
            ),
          ],
        ),
        CommunicationBoardDefinition(
          id: 'feelings',
          title: 'Feelings',
          homeEmoji: '😊',
          layout: CommunicationBoardLayout.grid,
          items: <CommunicationBoardItem>[
            CommunicationBoardItem(
              id: 'emotion-happy',
              label: 'Happy',
              speakText: 'Happy',
              emoji: '🙂',
            ),
            CommunicationBoardItem(
              id: 'emotion-sad',
              label: 'Sad',
              speakText: 'Sad',
              emoji: '🙁',
            ),
            CommunicationBoardItem(
              id: 'emotion-angry',
              label: 'Angry',
              speakText: 'Angry',
              emoji: '😡',
            ),
            CommunicationBoardItem(
              id: 'emotion-serious',
              label: 'Serious',
              speakText: 'Serious',
              emoji: '😐',
            ),
          ],
        ),
        CommunicationBoardDefinition(
          id: 'alphabets',
          title: 'Alphabets',
          homeEmoji: '🔤',
          layout: CommunicationBoardLayout.alphabets,
          items: <CommunicationBoardItem>[
            CommunicationBoardItem(id: 'letter-a', label: 'A', speakText: 'A'),
            CommunicationBoardItem(id: 'letter-b', label: 'B', speakText: 'B'),
            CommunicationBoardItem(id: 'letter-c', label: 'C', speakText: 'C'),
            CommunicationBoardItem(id: 'letter-d', label: 'D', speakText: 'D'),
            CommunicationBoardItem(id: 'letter-e', label: 'E', speakText: 'E'),
            CommunicationBoardItem(id: 'letter-f', label: 'F', speakText: 'F'),
            CommunicationBoardItem(id: 'letter-g', label: 'G', speakText: 'G'),
            CommunicationBoardItem(id: 'letter-h', label: 'H', speakText: 'H'),
            CommunicationBoardItem(id: 'letter-i', label: 'I', speakText: 'I'),
            CommunicationBoardItem(id: 'letter-j', label: 'J', speakText: 'J'),
            CommunicationBoardItem(id: 'letter-k', label: 'K', speakText: 'K'),
            CommunicationBoardItem(id: 'letter-l', label: 'L', speakText: 'L'),
            CommunicationBoardItem(id: 'letter-m', label: 'M', speakText: 'M'),
            CommunicationBoardItem(id: 'letter-n', label: 'N', speakText: 'N'),
            CommunicationBoardItem(id: 'letter-o', label: 'O', speakText: 'O'),
            CommunicationBoardItem(id: 'letter-p', label: 'P', speakText: 'P'),
            CommunicationBoardItem(id: 'letter-q', label: 'Q', speakText: 'Q'),
            CommunicationBoardItem(id: 'letter-r', label: 'R', speakText: 'R'),
            CommunicationBoardItem(id: 'letter-s', label: 'S', speakText: 'S'),
            CommunicationBoardItem(id: 'letter-t', label: 'T', speakText: 'T'),
            CommunicationBoardItem(id: 'letter-u', label: 'U', speakText: 'U'),
            CommunicationBoardItem(id: 'letter-v', label: 'V', speakText: 'V'),
            CommunicationBoardItem(id: 'letter-w', label: 'W', speakText: 'W'),
            CommunicationBoardItem(id: 'letter-x', label: 'X', speakText: 'X'),
            CommunicationBoardItem(id: 'letter-y', label: 'Y', speakText: 'Y'),
            CommunicationBoardItem(id: 'letter-z', label: 'Z', speakText: 'Z'),
          ],
        ),
        CommunicationBoardDefinition(
          id: 'clothes',
          title: 'Clothes',
          homeEmoji: '\u{1F455}',
          layout: CommunicationBoardLayout.grid,
          items: <CommunicationBoardItem>[
            CommunicationBoardItem(
              id: 'cloth-shirt',
              label: 'Shirt',
              speakText: 'Shirt',
              emoji: '\u{1F455}',
            ),
            CommunicationBoardItem(
              id: 'cloth-pants',
              label: 'Pants',
              speakText: 'Pants',
              emoji: '\u{1F456}',
            ),
            CommunicationBoardItem(
              id: 'cloth-shoes',
              label: 'Shoes',
              speakText: 'Shoes',
              emoji: '\u{1F45F}',
            ),
            CommunicationBoardItem(
              id: 'cloth-jacket',
              label: 'Jacket',
              speakText: 'Jacket',
              emoji: '\u{1F9E5}',
            ),
          ],
        ),
        CommunicationBoardDefinition(
          id: 'emergency',
          title: 'Emergency',
          homeEmoji: '🚨',
          layout: CommunicationBoardLayout.grid,
          items: <CommunicationBoardItem>[
            CommunicationBoardItem(
              id: 'emergency-help',
              label: 'Help',
              speakText: 'I need help',
              emoji: '🆘',
            ),
            CommunicationBoardItem(
              id: 'emergency-break',
              label: 'Break',
              speakText: 'I need a break',
              emoji: '⏸️',
            ),
            CommunicationBoardItem(
              id: 'emergency-too-loud',
              label: 'Too Loud',
              speakText: 'It is too loud',
              emoji: '🔊',
            ),
            CommunicationBoardItem(
              id: 'emergency-too-bright',
              label: 'Too Bright',
              speakText: 'It is too bright',
              emoji: '💡',
            ),
            CommunicationBoardItem(
              id: 'emergency-stop',
              label: 'Stop',
              speakText: 'Please stop',
              emoji: '🛑',
            ),
            CommunicationBoardItem(
              id: 'emergency-no-touch',
              label: 'No Touch',
              speakText: 'Please do not touch me',
              emoji: '✋',
            ),
            CommunicationBoardItem(
              id: 'emergency-water',
              label: 'Water',
              speakText: 'I need water',
              emoji: '💧',
            ),
            CommunicationBoardItem(
              id: 'emergency-bathroom',
              label: 'Bathroom',
              speakText: 'I need to use the bathroom',
              emoji: '🚻',
            ),
          ],
        ),
        CommunicationBoardDefinition(
          id: 'food',
          title: 'Food',
          homeEmoji: '🍔',
          layout: CommunicationBoardLayout.grid,
          items: <CommunicationBoardItem>[
            CommunicationBoardItem(
              id: 'food-roti',
              label: 'Roti',
              speakText: 'Roti',
              emoji: '🫓',
            ),
            CommunicationBoardItem(
              id: 'food-fruits',
              label: 'Fruits',
              speakText: 'Fruits',
              emoji: '🍎',
            ),
            CommunicationBoardItem(
              id: 'food-vegetables',
              label: 'Vegetables',
              speakText: 'Vegetables',
              emoji: '🥕',
            ),
            CommunicationBoardItem(
              id: 'food-yogurt',
              label: 'Yogurt',
              speakText: 'Yogurt',
              emoji: '🥣',
            ),
          ],
        ),
        CommunicationBoardDefinition(
          id: 'family',
          title: 'Family',
          homeEmoji: '👨‍👩‍👧‍👦',
          layout: CommunicationBoardLayout.grid,
          items: <CommunicationBoardItem>[
            CommunicationBoardItem(
              id: 'family-father',
              label: 'Father',
              speakText: 'Father',
              emoji: '👨',
            ),
            CommunicationBoardItem(
              id: 'family-mother',
              label: 'Mother',
              speakText: 'Mother',
              emoji: '👩',
            ),
            CommunicationBoardItem(
              id: 'family-brother',
              label: 'Brother',
              speakText: 'Brother',
              emoji: '🧒',
            ),
            CommunicationBoardItem(
              id: 'family-sister',
              label: 'Sister',
              speakText: 'Sister',
              emoji: '👧',
            ),
          ],
        ),
        CommunicationBoardDefinition(
          id: 'shapes',
          title: 'Shapes',
          homeEmoji: '⭐',
          layout: CommunicationBoardLayout.grid,
          items: <CommunicationBoardItem>[
            CommunicationBoardItem(
              id: 'shape-triangle',
              label: 'Triangle',
              speakText: 'Triangle',
              symbol: '▲',
              symbolColor: Color(0xFF4F6F32),
            ),
            CommunicationBoardItem(
              id: 'shape-star',
              label: 'Star',
              speakText: 'Star',
              symbol: '★',
              symbolColor: Color(0xFFE526E6),
            ),
            CommunicationBoardItem(
              id: 'shape-rectangle',
              label: 'Rectangle',
              speakText: 'Rectangle',
              symbol: '▬',
              symbolColor: Color(0xFFA3383A),
            ),
            CommunicationBoardItem(
              id: 'shape-square',
              label: 'Square',
              speakText: 'Square',
              symbol: '■',
              symbolColor: Color(0xFF2F98EB),
            ),
            CommunicationBoardItem(
              id: 'shape-heart',
              label: 'Heart',
              speakText: 'Heart',
              symbol: '♥',
              symbolColor: Color(0xFFFF3D8F),
            ),
            CommunicationBoardItem(
              id: 'shape-circle',
              label: 'Circle',
              speakText: 'Circle',
              symbol: '●',
              symbolColor: Color(0xFF3F717D),
            ),
          ],
        ),
        CommunicationBoardDefinition(
          id: 'emotions',
          title: 'Emotions',
          homeEmoji: '🙂',
          layout: CommunicationBoardLayout.grid,
          items: <CommunicationBoardItem>[
            CommunicationBoardItem(
              id: 'emotion-happy-alt',
              label: 'Happy',
              speakText: 'Happy',
              emoji: '🙂',
            ),
            CommunicationBoardItem(
              id: 'emotion-sad-alt',
              label: 'Sad',
              speakText: 'Sad',
              emoji: '🙁',
            ),
            CommunicationBoardItem(
              id: 'emotion-angry-alt',
              label: 'Angry',
              speakText: 'Angry',
              emoji: '😡',
            ),
            CommunicationBoardItem(
              id: 'emotion-serious-alt',
              label: 'Serious',
              speakText: 'Serious',
              emoji: '😐',
            ),
          ],
        ),
      ];

  static CommunicationBoardDefinition? boardForId(String id) {
    for (final board in boards) {
      if (board.id == id) {
        return board;
      }
    }
    return null;
  }

  static bool isHiddenBoardId(String id) {
    return hiddenBoardIds.contains(id.trim().toLowerCase());
  }

  static bool isHiddenBoardTitle(String title) {
    return hiddenBoardTitles.contains(title.trim().toLowerCase());
  }
}
