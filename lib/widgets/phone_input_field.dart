import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/responsive.dart';

/// Represents a supported country with dialing code.
class PhoneCountry {
  const PhoneCountry({
    required this.name,
    required this.code,
    required this.dialCode,
    required this.flag,
    required this.digitCount,
    required this.pattern,
  });

  final String name;
  final String code;
  final String dialCode;
  final String flag;
  // Expected local digit count (used for soft validation hint)
  final int digitCount;
  // The layout pattern for formatting (e.g. '### #######')
  final String pattern;
}

/// The list of supported countries for the phone picker.
const List<PhoneCountry> kSupportedCountries = [
  PhoneCountry(
    name: 'Pakistan',
    code: 'PK',
    dialCode: '+92',
    flag: '🇵🇰',
    digitCount: 10,
    pattern: '### #######',
  ),
  PhoneCountry(
    name: 'Malaysia',
    code: 'MY',
    dialCode: '+60',
    flag: '🇲🇾',
    digitCount: 9,
    pattern: '## ### ####',
  ),
  PhoneCountry(
    name: 'Indonesia',
    code: 'ID',
    dialCode: '+62',
    flag: '🇮🇩',
    digitCount: 11,
    pattern: '### #### ####',
  ),
  PhoneCountry(
    name: 'Singapore',
    code: 'SG',
    dialCode: '+65',
    flag: '🇸🇬',
    digitCount: 8,
    pattern: '#### ####',
  ),
  PhoneCountry(
    name: 'United Arab Emirates',
    code: 'AE',
    dialCode: '+971',
    flag: '🇦🇪',
    digitCount: 9,
    pattern: '## ### ####',
  ),
  PhoneCountry(
    name: 'Saudi Arabia',
    code: 'SA',
    dialCode: '+966',
    flag: '🇸🇦',
    digitCount: 9,
    pattern: '## ### ####',
  ),
  PhoneCountry(
    name: 'United Kingdom',
    code: 'GB',
    dialCode: '+44',
    flag: '🇬🇧',
    digitCount: 10,
    pattern: '#### ######',
  ),
  PhoneCountry(
    name: 'United States',
    code: 'US',
    dialCode: '+1',
    flag: '🇺🇸',
    digitCount: 10,
    pattern: '(###) ###-####',
  ),
  PhoneCountry(
    name: 'Canada',
    code: 'CA',
    dialCode: '+1',
    flag: '🇨🇦',
    digitCount: 10,
    pattern: '(###) ###-####',
  ),
  PhoneCountry(
    name: 'India',
    code: 'IN',
    dialCode: '+91',
    flag: '🇮🇳',
    digitCount: 10,
    pattern: '##### #####',
  ),
  PhoneCountry(
    name: 'Bangladesh',
    code: 'BD',
    dialCode: '+880',
    flag: '🇧🇩',
    digitCount: 10,
    pattern: '#### ######',
  ),
  PhoneCountry(
    name: 'Australia',
    code: 'AU',
    dialCode: '+61',
    flag: '🇦🇺',
    digitCount: 9,
    pattern: '### ### ###',
  ),
  PhoneCountry(
    name: 'New Zealand',
    code: 'NZ',
    dialCode: '+64',
    flag: '🇳🇿',
    digitCount: 9,
    pattern: '### ### ###',
  ),
  PhoneCountry(
    name: 'Germany',
    code: 'DE',
    dialCode: '+49',
    flag: '🇩🇪',
    digitCount: 10,
    pattern: '#### #######',
  ),
  PhoneCountry(
    name: 'France',
    code: 'FR',
    dialCode: '+33',
    flag: '🇫🇷',
    digitCount: 9,
    pattern: '# ## ## ## ##',
  ),
  PhoneCountry(
    name: 'Spain',
    code: 'ES',
    dialCode: '+34',
    flag: '🇪🇸',
    digitCount: 9,
    pattern: '### ## ## ##',
  ),
  PhoneCountry(
    name: 'Italy',
    code: 'IT',
    dialCode: '+39',
    flag: '🇮🇹',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Brazil',
    code: 'BR',
    dialCode: '+55',
    flag: '🇧🇷',
    digitCount: 11,
    pattern: '## #####-####',
  ),
  PhoneCountry(
    name: 'Mexico',
    code: 'MX',
    dialCode: '+52',
    flag: '🇲🇽',
    digitCount: 10,
    pattern: '## ## #### ####',
  ),
  PhoneCountry(
    name: 'Egypt',
    code: 'EG',
    dialCode: '+20',
    flag: '🇪🇬',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'South Africa',
    code: 'ZA',
    dialCode: '+27',
    flag: '🇿🇦',
    digitCount: 9,
    pattern: '## ### ####',
  ),
  PhoneCountry(
    name: 'Nigeria',
    code: 'NG',
    dialCode: '+234',
    flag: '🇳🇬',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Japan',
    code: 'JP',
    dialCode: '+81',
    flag: '🇯🇵',
    digitCount: 10,
    pattern: '## #### ####',
  ),
  PhoneCountry(
    name: 'South Korea',
    code: 'KR',
    dialCode: '+82',
    flag: '🇰🇷',
    digitCount: 10,
    pattern: '### #### ####',
  ),
  PhoneCountry(
    name: 'China',
    code: 'CN',
    dialCode: '+86',
    flag: '🇨🇳',
    digitCount: 11,
    pattern: '### #### ####',
  ),
  PhoneCountry(
    name: 'Philippines',
    code: 'PH',
    dialCode: '+63',
    flag: '🇵🇭',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Thailand',
    code: 'TH',
    dialCode: '+66',
    flag: '🇹🇭',
    digitCount: 9,
    pattern: '## #### ####',
  ),
  PhoneCountry(
    name: 'Vietnam',
    code: 'VN',
    dialCode: '+84',
    flag: '🇻🇳',
    digitCount: 9,
    pattern: '## #### ####',
  ),
  PhoneCountry(
    name: 'Turkey',
    code: 'TR',
    dialCode: '+90',
    flag: '🇹🇷',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Qatar',
    code: 'QA',
    dialCode: '+974',
    flag: '🇶🇦',
    digitCount: 8,
    pattern: '#### ####',
  ),
  PhoneCountry(
    name: 'Kuwait',
    code: 'KW',
    dialCode: '+965',
    flag: '🇰🇼',
    digitCount: 8,
    pattern: '#### ####',
  ),
  PhoneCountry(
    name: 'Oman',
    code: 'OM',
    dialCode: '+968',
    flag: '🇴🇲',
    digitCount: 8,
    pattern: '#### ####',
  ),
  PhoneCountry(
    name: 'Bahrain',
    code: 'BH',
    dialCode: '+973',
    flag: '🇧🇭',
    digitCount: 8,
    pattern: '#### ####',
  ),
  PhoneCountry(
    name: 'Jordan',
    code: 'JO',
    dialCode: '+962',
    flag: '🇯🇴',
    digitCount: 9,
    pattern: '## ### ####',
  ),
  PhoneCountry(
    name: 'Lebanon',
    code: 'LB',
    dialCode: '+961',
    flag: '🇱🇧',
    digitCount: 8,
    pattern: '## ### ###',
  ),
];

/// Returns the full international phone number string (dialCode + localNumber)
/// that should be saved to Firestore.
String buildFullPhoneNumber(PhoneCountry country, String localNumber) {
  final digits = localNumber.replaceAll(RegExp(r'[^\d]'), '');
  return '${country.dialCode}$digits';
}

/// Given a raw stored phone number (e.g. "+923001234567"), tries to find a
/// matching country and returns [country, localDigits]. Falls back to Pakistan.
(PhoneCountry, String) parseStoredPhoneNumber(String stored) {
  for (final country in kSupportedCountries) {
    if (stored.startsWith(country.dialCode)) {
      final local = stored.substring(country.dialCode.length);
      return (country, local);
    }
  }
  return (kSupportedCountries.first, stored.replaceAll(RegExp(r'[^\d]'), ''));
}

/// A reusable phone input field with country selection dropdown,
/// digit-only input, and a live preview of the full number.
class PhoneInputField extends StatefulWidget {
  const PhoneInputField({
    super.key,
    required this.localController,
    this.initialCountry,
    this.onCountryChanged,
    this.labelStyle,
    this.fieldDecoration,
    this.showPreview = true,
  });

  /// The text controller for the local (national) part of the number.
  final TextEditingController localController;

  /// Pre-selected country; defaults to Pakistan.
  final PhoneCountry? initialCountry;

  /// Called whenever the selected country changes.
  final ValueChanged<PhoneCountry>? onCountryChanged;

  /// Optional custom label text style.
  final TextStyle? labelStyle;

  /// Optional decoration overrides.
  final BoxDecoration? fieldDecoration;

  /// Whether to show the "Your number will be saved as …" preview line.
  final bool showPreview;

  @override
  State<PhoneInputField> createState() => PhoneInputFieldState();
}

class PhoneInputFieldState extends State<PhoneInputField> {
  late PhoneCountry _selectedCountry;

  PhoneCountry get selectedCountry => _selectedCountry;

  @override
  void initState() {
    super.initState();
    _selectedCountry = widget.initialCountry ?? kSupportedCountries.first;
  }

  String get _preview {
    final digits = widget.localController.text.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.isEmpty) return '';
    return '${_selectedCountry.dialCode} $digits';
  }

  @override
  Widget build(BuildContext context) {
    final r = context.responsive;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Row: flag dropdown + number input ──────────────────────────────
        Container(
          decoration: widget.fieldDecoration ??
              BoxDecoration(
                color: const Color(0xFFF4F7FB),
                borderRadius: BorderRadius.circular(r.w(16)),
                border: Border.all(color: const Color(0xFFD2DCE6)),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFB0C4DE).withValues(alpha: 0.4),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
          child: Row(
            children: [
              // Country dropdown
              _CountryDropdown(
                selected: _selectedCountry,
                onChanged: (country) {
                  setState(() {
                    _selectedCountry = country;
                  });
                  // Re-format current text with new country formatter
                  final text = widget.localController.text;
                  final formatter = PhoneTextInputFormatter(() => country);
                  final rawSelection = widget.localController.selection;
                  final formatted = formatter.formatEditUpdate(
                    TextEditingValue.empty,
                    TextEditingValue(
                      text: text,
                      selection: rawSelection,
                    ),
                  );
                  widget.localController.value = formatted;
                  widget.onCountryChanged?.call(country);
                },
              ),
              // Divider
              Container(
                width: 1,
                height: r.h(24),
                color: const Color(0xFFD2DCE6),
              ),
              // Local number field
              Expanded(
                child: TextField(
                  controller: widget.localController,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    PhoneTextInputFormatter(() => _selectedCountry),
                  ],
                  style: TextStyle(
                    fontSize: r.sp(16, min: 14, max: 20),
                    color: const Color(0xFF1A2543),
                    fontWeight: FontWeight.w500,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Phone number',
                    hintStyle: TextStyle(
                      color: const Color(0xFFA0AEC0),
                      fontSize: r.sp(14, min: 12, max: 16),
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: r.w(12),
                      vertical: r.h(15),
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
        ),

        // ── Live preview ───────────────────────────────────────────────────
        if (widget.showPreview && _preview.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(top: r.h(6), left: r.w(4)),
            child: Text(
              'Your number will be saved as: $_preview',
              style: TextStyle(
                fontSize: r.sp(11, min: 10, max: 13),
                color: const Color(0xFF4EA9E3),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────

class _CountryDropdown extends StatelessWidget {
  const _CountryDropdown({
    required this.selected,
    required this.onChanged,
  });

  final PhoneCountry selected;
  final ValueChanged<PhoneCountry> onChanged;

  @override
  Widget build(BuildContext context) {
    final r = context.responsive;

    return PopupMenuButton<PhoneCountry>(
      initialValue: selected,
      onSelected: onChanged,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      itemBuilder: (_) => kSupportedCountries
          .map(
            (c) => PopupMenuItem<PhoneCountry>(
              value: c,
              child: Row(
                children: [
                  Text(c.flag, style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      c.name,
                      style: const TextStyle(fontSize: 14),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    c.dialCode,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF4EA9E3),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: r.w(10),
          vertical: r.h(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(selected.flag, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 4),
            Text(
              selected.dialCode,
              style: TextStyle(
                fontSize: r.sp(13, min: 11, max: 15),
                fontWeight: FontWeight.w600,
                color: const Color(0xFF1A2543),
              ),
            ),
            const SizedBox(width: 2),
            const Icon(Icons.arrow_drop_down, size: 18, color: Color(0xFF888888)),
          ],
        ),
      ),
    );
  }
}

/// Automatically formats the phone input field based on country patterns.
class PhoneTextInputFormatter extends TextInputFormatter {
  PhoneTextInputFormatter(this.countryProvider);

  final PhoneCountry Function() countryProvider;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final pattern = countryProvider().pattern;
    final text = newValue.text;
    final oldText = oldValue.text;
    
    bool isDeleting = text.length < oldText.length;
    String digits = text.replaceAll(RegExp(r'[^\d]'), '');
    
    if (isDeleting && oldValue.selection.end > 0) {
      final deletedCharIdx = oldValue.selection.end - 1;
      if (deletedCharIdx < oldText.length) {
        final deletedChar = oldText[deletedCharIdx];
        if (!RegExp(r'\d').hasMatch(deletedChar)) {
          int lastDigitIdx = -1;
          for (int i = deletedCharIdx - 1; i >= 0; i--) {
            if (RegExp(r'\d').hasMatch(oldText[i])) {
              lastDigitIdx = i;
              break;
            }
          }
          if (lastDigitIdx != -1) {
            int digitCount = 0;
            for (int i = 0; i <= lastDigitIdx; i++) {
              if (RegExp(r'\d').hasMatch(oldText[i])) {
                digitCount++;
              }
            }
            final oldDigits = oldText.replaceAll(RegExp(r'[^\d]'), '');
            if (digitCount <= oldDigits.length) {
              digits = oldDigits.substring(0, digitCount - 1) + oldDigits.substring(digitCount);
            }
          }
        }
      }
    }
    
    final formatted = StringBuffer();
    int digitIndex = 0;
    
    for (int i = 0; i < pattern.length; i++) {
      if (digitIndex >= digits.length) break;
      
      final char = pattern[i];
      if (char == '#') {
        formatted.write(digits[digitIndex]);
        digitIndex++;
      } else {
        formatted.write(char);
      }
    }
    
    if (digitIndex < digits.length) {
      final remaining = digits.substring(digitIndex);
      final spaceLeft = 15 - formatted.length;
      if (spaceLeft > 0) {
        formatted.write(remaining.substring(0, math.min(remaining.length, spaceLeft)));
      }
    }
    
    final formattedText = formatted.toString();
    int newSelectionIndex = 0;
    
    if (newValue.selection.end >= 0) {
      int rawDigitsBeforeCursor = 0;
      for (int i = 0; i < newValue.selection.end && i < text.length; i++) {
        if (RegExp(r'\d').hasMatch(text[i])) {
          rawDigitsBeforeCursor++;
        }
      }
      
      if (isDeleting && oldValue.selection.end > 0) {
        final deletedCharIdx = oldValue.selection.end - 1;
        if (deletedCharIdx < oldText.length && !RegExp(r'\d').hasMatch(oldText[deletedCharIdx])) {
          rawDigitsBeforeCursor = math.max(0, rawDigitsBeforeCursor - 1);
        }
      }
      
      int digitsFound = 0;
      for (int i = 0; i < formattedText.length; i++) {
        if (digitsFound >= rawDigitsBeforeCursor) {
          break;
        }
        if (RegExp(r'\d').hasMatch(formattedText[i])) {
          digitsFound++;
        }
        newSelectionIndex = i + 1;
      }
    } else {
      newSelectionIndex = formattedText.length;
    }
    
    return TextEditingValue(
      text: formattedText,
      selection: TextSelection.collapsed(offset: newSelectionIndex),
    );
  }
}
