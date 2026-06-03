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
    name: 'Afghanistan',
    code: 'AF',
    dialCode: '+93',
    flag: '🇦🇫',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Åland Islands',
    code: 'AX',
    dialCode: '+358',
    flag: '🇦🇽',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Albania',
    code: 'AL',
    dialCode: '+355',
    flag: '🇦🇱',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Algeria',
    code: 'DZ',
    dialCode: '+213',
    flag: '🇩🇿',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'American Samoa',
    code: 'AS',
    dialCode: '+1684',
    flag: '🇦🇸',
    digitCount: 7,
    pattern: '### ####',
  ),
  PhoneCountry(
    name: 'Andorra',
    code: 'AD',
    dialCode: '+376',
    flag: '🇦🇩',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Angola',
    code: 'AO',
    dialCode: '+244',
    flag: '🇦🇴',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Anguilla',
    code: 'AI',
    dialCode: '+1264',
    flag: '🇦🇮',
    digitCount: 7,
    pattern: '### ####',
  ),
  PhoneCountry(
    name: 'Antarctica',
    code: 'AQ',
    dialCode: '+672',
    flag: '🇦🇶',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Antigua and Barbuda',
    code: 'AG',
    dialCode: '+1268',
    flag: '🇦🇬',
    digitCount: 7,
    pattern: '### ####',
  ),
  PhoneCountry(
    name: 'Argentina',
    code: 'AR',
    dialCode: '+54',
    flag: '🇦🇷',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Armenia',
    code: 'AM',
    dialCode: '+374',
    flag: '🇦🇲',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Aruba',
    code: 'AW',
    dialCode: '+297',
    flag: '🇦🇼',
    digitCount: 10,
    pattern: '### ### ####',
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
    name: 'Austria',
    code: 'AT',
    dialCode: '+43',
    flag: '🇦🇹',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Azerbaijan',
    code: 'AZ',
    dialCode: '+994',
    flag: '🇦🇿',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Bahamas',
    code: 'BS',
    dialCode: '+1242',
    flag: '🇧🇸',
    digitCount: 7,
    pattern: '### ####',
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
    name: 'Bangladesh',
    code: 'BD',
    dialCode: '+880',
    flag: '🇧🇩',
    digitCount: 10,
    pattern: '#### ######',
  ),
  PhoneCountry(
    name: 'Barbados',
    code: 'BB',
    dialCode: '+1246',
    flag: '🇧🇧',
    digitCount: 7,
    pattern: '### ####',
  ),
  PhoneCountry(
    name: 'Belarus',
    code: 'BY',
    dialCode: '+375',
    flag: '🇧🇾',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Belgium',
    code: 'BE',
    dialCode: '+32',
    flag: '🇧🇪',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Belize',
    code: 'BZ',
    dialCode: '+501',
    flag: '🇧🇿',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Benin',
    code: 'BJ',
    dialCode: '+229',
    flag: '🇧🇯',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Bermuda',
    code: 'BM',
    dialCode: '+1441',
    flag: '🇧🇲',
    digitCount: 7,
    pattern: '### ####',
  ),
  PhoneCountry(
    name: 'Bhutan',
    code: 'BT',
    dialCode: '+975',
    flag: '🇧🇹',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Bolivia, Plurinational State of bolivia',
    code: 'BO',
    dialCode: '+591',
    flag: '🇧🇴',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Bosnia and Herzegovina',
    code: 'BA',
    dialCode: '+387',
    flag: '🇧🇦',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Botswana',
    code: 'BW',
    dialCode: '+267',
    flag: '🇧🇼',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Bouvet Island',
    code: 'BV',
    dialCode: '+47',
    flag: '🇧🇻',
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
    name: 'British Indian Ocean Territory',
    code: 'IO',
    dialCode: '+246',
    flag: '🇮🇴',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Brunei Darussalam',
    code: 'BN',
    dialCode: '+673',
    flag: '🇧🇳',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Bulgaria',
    code: 'BG',
    dialCode: '+359',
    flag: '🇧🇬',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Burkina Faso',
    code: 'BF',
    dialCode: '+226',
    flag: '🇧🇫',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Burundi',
    code: 'BI',
    dialCode: '+257',
    flag: '🇧🇮',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Cambodia',
    code: 'KH',
    dialCode: '+855',
    flag: '🇰🇭',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Cameroon',
    code: 'CM',
    dialCode: '+237',
    flag: '🇨🇲',
    digitCount: 10,
    pattern: '### ### ####',
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
    name: 'Cape Verde',
    code: 'CV',
    dialCode: '+238',
    flag: '🇨🇻',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Cayman Islands',
    code: 'KY',
    dialCode: '+345',
    flag: '🇰🇾',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Central African Republic',
    code: 'CF',
    dialCode: '+236',
    flag: '🇨🇫',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Chad',
    code: 'TD',
    dialCode: '+235',
    flag: '🇹🇩',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Chile',
    code: 'CL',
    dialCode: '+56',
    flag: '🇨🇱',
    digitCount: 10,
    pattern: '### ### ####',
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
    name: 'Christmas Island',
    code: 'CX',
    dialCode: '+61',
    flag: '🇨🇽',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Cocos (Keeling) Islands',
    code: 'CC',
    dialCode: '+61',
    flag: '🇨🇨',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Colombia',
    code: 'CO',
    dialCode: '+57',
    flag: '🇨🇴',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Comoros',
    code: 'KM',
    dialCode: '+269',
    flag: '🇰🇲',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Congo',
    code: 'CG',
    dialCode: '+242',
    flag: '🇨🇬',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Congo, The Democratic Republic of the Congo',
    code: 'CD',
    dialCode: '+243',
    flag: '🇨🇩',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Cook Islands',
    code: 'CK',
    dialCode: '+682',
    flag: '🇨🇰',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Costa Rica',
    code: 'CR',
    dialCode: '+506',
    flag: '🇨🇷',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Cote d\'Ivoire',
    code: 'CI',
    dialCode: '+225',
    flag: '🇨🇮',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Croatia',
    code: 'HR',
    dialCode: '+385',
    flag: '🇭🇷',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Cuba',
    code: 'CU',
    dialCode: '+53',
    flag: '🇨🇺',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Cyprus',
    code: 'CY',
    dialCode: '+357',
    flag: '🇨🇾',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Czech Republic',
    code: 'CZ',
    dialCode: '+420',
    flag: '🇨🇿',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Denmark',
    code: 'DK',
    dialCode: '+45',
    flag: '🇩🇰',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Djibouti',
    code: 'DJ',
    dialCode: '+253',
    flag: '🇩🇯',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Dominica',
    code: 'DM',
    dialCode: '+1767',
    flag: '🇩🇲',
    digitCount: 7,
    pattern: '### ####',
  ),
  PhoneCountry(
    name: 'Dominican Republic',
    code: 'DO',
    dialCode: '+1849',
    flag: '🇩🇴',
    digitCount: 7,
    pattern: '### ####',
  ),
  PhoneCountry(
    name: 'Ecuador',
    code: 'EC',
    dialCode: '+593',
    flag: '🇪🇨',
    digitCount: 10,
    pattern: '### ### ####',
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
    name: 'El Salvador',
    code: 'SV',
    dialCode: '+503',
    flag: '🇸🇻',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Equatorial Guinea',
    code: 'GQ',
    dialCode: '+240',
    flag: '🇬🇶',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Eritrea',
    code: 'ER',
    dialCode: '+291',
    flag: '🇪🇷',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Estonia',
    code: 'EE',
    dialCode: '+372',
    flag: '🇪🇪',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Ethiopia',
    code: 'ET',
    dialCode: '+251',
    flag: '🇪🇹',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Falkland Islands (Malvinas)',
    code: 'FK',
    dialCode: '+500',
    flag: '🇫🇰',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Faroe Islands',
    code: 'FO',
    dialCode: '+298',
    flag: '🇫🇴',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Fiji',
    code: 'FJ',
    dialCode: '+679',
    flag: '🇫🇯',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Finland',
    code: 'FI',
    dialCode: '+358',
    flag: '🇫🇮',
    digitCount: 10,
    pattern: '### ### ####',
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
    name: 'French Guiana',
    code: 'GF',
    dialCode: '+594',
    flag: '🇬🇫',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'French Polynesia',
    code: 'PF',
    dialCode: '+689',
    flag: '🇵🇫',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'French Southern Territories',
    code: 'TF',
    dialCode: '+262',
    flag: '🇹🇫',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Gabon',
    code: 'GA',
    dialCode: '+241',
    flag: '🇬🇦',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Gambia',
    code: 'GM',
    dialCode: '+220',
    flag: '🇬🇲',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Georgia',
    code: 'GE',
    dialCode: '+995',
    flag: '🇬🇪',
    digitCount: 10,
    pattern: '### ### ####',
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
    name: 'Ghana',
    code: 'GH',
    dialCode: '+233',
    flag: '🇬🇭',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Gibraltar',
    code: 'GI',
    dialCode: '+350',
    flag: '🇬🇮',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Greece',
    code: 'GR',
    dialCode: '+30',
    flag: '🇬🇷',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Greenland',
    code: 'GL',
    dialCode: '+299',
    flag: '🇬🇱',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Grenada',
    code: 'GD',
    dialCode: '+1473',
    flag: '🇬🇩',
    digitCount: 7,
    pattern: '### ####',
  ),
  PhoneCountry(
    name: 'Guadeloupe',
    code: 'GP',
    dialCode: '+590',
    flag: '🇬🇵',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Guam',
    code: 'GU',
    dialCode: '+1671',
    flag: '🇬🇺',
    digitCount: 7,
    pattern: '### ####',
  ),
  PhoneCountry(
    name: 'Guatemala',
    code: 'GT',
    dialCode: '+502',
    flag: '🇬🇹',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Guernsey',
    code: 'GG',
    dialCode: '+44',
    flag: '🇬🇬',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Guinea',
    code: 'GN',
    dialCode: '+224',
    flag: '🇬🇳',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Guinea-Bissau',
    code: 'GW',
    dialCode: '+245',
    flag: '🇬🇼',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Guyana',
    code: 'GY',
    dialCode: '+592',
    flag: '🇬🇾',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Haiti',
    code: 'HT',
    dialCode: '+509',
    flag: '🇭🇹',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Heard Island and Mcdonald Islands',
    code: 'HM',
    dialCode: '+672',
    flag: '🇭🇲',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Holy See (Vatican City State)',
    code: 'VA',
    dialCode: '+379',
    flag: '🇻🇦',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Honduras',
    code: 'HN',
    dialCode: '+504',
    flag: '🇭🇳',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Hong Kong',
    code: 'HK',
    dialCode: '+852',
    flag: '🇭🇰',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Hungary',
    code: 'HU',
    dialCode: '+36',
    flag: '🇭🇺',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Iceland',
    code: 'IS',
    dialCode: '+354',
    flag: '🇮🇸',
    digitCount: 10,
    pattern: '### ### ####',
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
    name: 'Indonesia',
    code: 'ID',
    dialCode: '+62',
    flag: '🇮🇩',
    digitCount: 11,
    pattern: '### #### ####',
  ),
  PhoneCountry(
    name: 'Iran, Islamic Republic of Persian Gulf',
    code: 'IR',
    dialCode: '+98',
    flag: '🇮🇷',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Iraq',
    code: 'IQ',
    dialCode: '+964',
    flag: '🇮🇶',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Ireland',
    code: 'IE',
    dialCode: '+353',
    flag: '🇮🇪',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Isle of Man',
    code: 'IM',
    dialCode: '+44',
    flag: '🇮🇲',
    digitCount: 10,
    pattern: '### ### ####',
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
    name: 'Jamaica',
    code: 'JM',
    dialCode: '+1876',
    flag: '🇯🇲',
    digitCount: 7,
    pattern: '### ####',
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
    name: 'Jersey',
    code: 'JE',
    dialCode: '+44',
    flag: '🇯🇪',
    digitCount: 10,
    pattern: '### ### ####',
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
    name: 'Kazakhstan',
    code: 'KZ',
    dialCode: '+7',
    flag: '🇰🇿',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Kenya',
    code: 'KE',
    dialCode: '+254',
    flag: '🇰🇪',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Kiribati',
    code: 'KI',
    dialCode: '+686',
    flag: '🇰🇮',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Korea, Democratic People\'s Republic of Korea',
    code: 'KP',
    dialCode: '+850',
    flag: '🇰🇵',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Korea, Republic of South Korea',
    code: 'KR',
    dialCode: '+82',
    flag: '🇰🇷',
    digitCount: 10,
    pattern: '### #### ####',
  ),
  PhoneCountry(
    name: 'Kosovo',
    code: 'XK',
    dialCode: '+383',
    flag: '🇽🇰',
    digitCount: 10,
    pattern: '### ### ####',
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
    name: 'Kyrgyzstan',
    code: 'KG',
    dialCode: '+996',
    flag: '🇰🇬',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Laos',
    code: 'LA',
    dialCode: '+856',
    flag: '🇱🇦',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Latvia',
    code: 'LV',
    dialCode: '+371',
    flag: '🇱🇻',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Lebanon',
    code: 'LB',
    dialCode: '+961',
    flag: '🇱🇧',
    digitCount: 8,
    pattern: '## ### ###',
  ),
  PhoneCountry(
    name: 'Lesotho',
    code: 'LS',
    dialCode: '+266',
    flag: '🇱🇸',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Liberia',
    code: 'LR',
    dialCode: '+231',
    flag: '🇱🇷',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Libyan Arab Jamahiriya',
    code: 'LY',
    dialCode: '+218',
    flag: '🇱🇾',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Liechtenstein',
    code: 'LI',
    dialCode: '+423',
    flag: '🇱🇮',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Lithuania',
    code: 'LT',
    dialCode: '+370',
    flag: '🇱🇹',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Luxembourg',
    code: 'LU',
    dialCode: '+352',
    flag: '🇱🇺',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Macao',
    code: 'MO',
    dialCode: '+853',
    flag: '🇲🇴',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Macedonia',
    code: 'MK',
    dialCode: '+389',
    flag: '🇲🇰',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Madagascar',
    code: 'MG',
    dialCode: '+261',
    flag: '🇲🇬',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Malawi',
    code: 'MW',
    dialCode: '+265',
    flag: '🇲🇼',
    digitCount: 10,
    pattern: '### ### ####',
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
    name: 'Maldives',
    code: 'MV',
    dialCode: '+960',
    flag: '🇲🇻',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Mali',
    code: 'ML',
    dialCode: '+223',
    flag: '🇲🇱',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Malta',
    code: 'MT',
    dialCode: '+356',
    flag: '🇲🇹',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Marshall Islands',
    code: 'MH',
    dialCode: '+692',
    flag: '🇲🇭',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Martinique',
    code: 'MQ',
    dialCode: '+596',
    flag: '🇲🇶',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Mauritania',
    code: 'MR',
    dialCode: '+222',
    flag: '🇲🇷',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Mauritius',
    code: 'MU',
    dialCode: '+230',
    flag: '🇲🇺',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Mayotte',
    code: 'YT',
    dialCode: '+262',
    flag: '🇾🇹',
    digitCount: 10,
    pattern: '### ### ####',
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
    name: 'Micronesia, Federated States of Micronesia',
    code: 'FM',
    dialCode: '+691',
    flag: '🇫🇲',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Moldova',
    code: 'MD',
    dialCode: '+373',
    flag: '🇲🇩',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Monaco',
    code: 'MC',
    dialCode: '+377',
    flag: '🇲🇨',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Mongolia',
    code: 'MN',
    dialCode: '+976',
    flag: '🇲🇳',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Montenegro',
    code: 'ME',
    dialCode: '+382',
    flag: '🇲🇪',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Montserrat',
    code: 'MS',
    dialCode: '+1664',
    flag: '🇲🇸',
    digitCount: 7,
    pattern: '### ####',
  ),
  PhoneCountry(
    name: 'Morocco',
    code: 'MA',
    dialCode: '+212',
    flag: '🇲🇦',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Mozambique',
    code: 'MZ',
    dialCode: '+258',
    flag: '🇲🇿',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Myanmar',
    code: 'MM',
    dialCode: '+95',
    flag: '🇲🇲',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Namibia',
    code: 'NA',
    dialCode: '+264',
    flag: '🇳🇦',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Nauru',
    code: 'NR',
    dialCode: '+674',
    flag: '🇳🇷',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Nepal',
    code: 'NP',
    dialCode: '+977',
    flag: '🇳🇵',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Netherlands',
    code: 'NL',
    dialCode: '+31',
    flag: '🇳🇱',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Netherlands Antilles',
    code: 'AN',
    dialCode: '+599',
    flag: '',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'New Caledonia',
    code: 'NC',
    dialCode: '+687',
    flag: '🇳🇨',
    digitCount: 10,
    pattern: '### ### ####',
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
    name: 'Nicaragua',
    code: 'NI',
    dialCode: '+505',
    flag: '🇳🇮',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Niger',
    code: 'NE',
    dialCode: '+227',
    flag: '🇳🇪',
    digitCount: 10,
    pattern: '### ### ####',
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
    name: 'Niue',
    code: 'NU',
    dialCode: '+683',
    flag: '🇳🇺',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Norfolk Island',
    code: 'NF',
    dialCode: '+672',
    flag: '🇳🇫',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Northern Mariana Islands',
    code: 'MP',
    dialCode: '+1670',
    flag: '🇲🇵',
    digitCount: 7,
    pattern: '### ####',
  ),
  PhoneCountry(
    name: 'Norway',
    code: 'NO',
    dialCode: '+47',
    flag: '🇳🇴',
    digitCount: 10,
    pattern: '### ### ####',
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
    name: 'Pakistan',
    code: 'PK',
    dialCode: '+92',
    flag: '🇵🇰',
    digitCount: 10,
    pattern: '### #######',
  ),
  PhoneCountry(
    name: 'Palau',
    code: 'PW',
    dialCode: '+680',
    flag: '🇵🇼',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Palestinian Territory, Occupied',
    code: 'PS',
    dialCode: '+970',
    flag: '🇵🇸',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Panama',
    code: 'PA',
    dialCode: '+507',
    flag: '🇵🇦',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Papua New Guinea',
    code: 'PG',
    dialCode: '+675',
    flag: '🇵🇬',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Paraguay',
    code: 'PY',
    dialCode: '+595',
    flag: '🇵🇾',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Peru',
    code: 'PE',
    dialCode: '+51',
    flag: '🇵🇪',
    digitCount: 10,
    pattern: '### ### ####',
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
    name: 'Pitcairn',
    code: 'PN',
    dialCode: '+64',
    flag: '🇵🇳',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Poland',
    code: 'PL',
    dialCode: '+48',
    flag: '🇵🇱',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Portugal',
    code: 'PT',
    dialCode: '+351',
    flag: '🇵🇹',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Puerto Rico',
    code: 'PR',
    dialCode: '+1939',
    flag: '🇵🇷',
    digitCount: 7,
    pattern: '### ####',
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
    name: 'Romania',
    code: 'RO',
    dialCode: '+40',
    flag: '🇷🇴',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Russia',
    code: 'RU',
    dialCode: '+7',
    flag: '🇷🇺',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Rwanda',
    code: 'RW',
    dialCode: '+250',
    flag: '🇷🇼',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Reunion',
    code: 'RE',
    dialCode: '+262',
    flag: '🇷🇪',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Saint Barthelemy',
    code: 'BL',
    dialCode: '+590',
    flag: '🇧🇱',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Saint Helena, Ascension and Tristan Da Cunha',
    code: 'SH',
    dialCode: '+290',
    flag: '🇸🇭',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Saint Kitts and Nevis',
    code: 'KN',
    dialCode: '+1869',
    flag: '🇰🇳',
    digitCount: 7,
    pattern: '### ####',
  ),
  PhoneCountry(
    name: 'Saint Lucia',
    code: 'LC',
    dialCode: '+1758',
    flag: '🇱🇨',
    digitCount: 7,
    pattern: '### ####',
  ),
  PhoneCountry(
    name: 'Saint Martin',
    code: 'MF',
    dialCode: '+590',
    flag: '🇲🇫',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Saint Pierre and Miquelon',
    code: 'PM',
    dialCode: '+508',
    flag: '🇵🇲',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Saint Vincent and the Grenadines',
    code: 'VC',
    dialCode: '+1784',
    flag: '🇻🇨',
    digitCount: 7,
    pattern: '### ####',
  ),
  PhoneCountry(
    name: 'Samoa',
    code: 'WS',
    dialCode: '+685',
    flag: '🇼🇸',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'San Marino',
    code: 'SM',
    dialCode: '+378',
    flag: '🇸🇲',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Sao Tome and Principe',
    code: 'ST',
    dialCode: '+239',
    flag: '🇸🇹',
    digitCount: 10,
    pattern: '### ### ####',
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
    name: 'Senegal',
    code: 'SN',
    dialCode: '+221',
    flag: '🇸🇳',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Serbia',
    code: 'RS',
    dialCode: '+381',
    flag: '🇷🇸',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Seychelles',
    code: 'SC',
    dialCode: '+248',
    flag: '🇸🇨',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Sierra Leone',
    code: 'SL',
    dialCode: '+232',
    flag: '🇸🇱',
    digitCount: 10,
    pattern: '### ### ####',
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
    name: 'Slovakia',
    code: 'SK',
    dialCode: '+421',
    flag: '🇸🇰',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Slovenia',
    code: 'SI',
    dialCode: '+386',
    flag: '🇸🇮',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Solomon Islands',
    code: 'SB',
    dialCode: '+677',
    flag: '🇸🇧',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Somalia',
    code: 'SO',
    dialCode: '+252',
    flag: '🇸🇴',
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
    name: 'South Sudan',
    code: 'SS',
    dialCode: '+211',
    flag: '🇸🇸',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'South Georgia and the South Sandwich Islands',
    code: 'GS',
    dialCode: '+500',
    flag: '🇬🇸',
    digitCount: 10,
    pattern: '### ### ####',
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
    name: 'Sri Lanka',
    code: 'LK',
    dialCode: '+94',
    flag: '🇱🇰',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Sudan',
    code: 'SD',
    dialCode: '+249',
    flag: '🇸🇩',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Suriname',
    code: 'SR',
    dialCode: '+597',
    flag: '🇸🇷',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Svalbard and Jan Mayen',
    code: 'SJ',
    dialCode: '+47',
    flag: '🇸🇯',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Eswatini',
    code: 'SZ',
    dialCode: '+268',
    flag: '🇸🇿',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Sweden',
    code: 'SE',
    dialCode: '+46',
    flag: '🇸🇪',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Switzerland',
    code: 'CH',
    dialCode: '+41',
    flag: '🇨🇭',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Syrian Arab Republic',
    code: 'SY',
    dialCode: '+963',
    flag: '🇸🇾',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Taiwan',
    code: 'TW',
    dialCode: '+886',
    flag: '🇹🇼',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Tajikistan',
    code: 'TJ',
    dialCode: '+992',
    flag: '🇹🇯',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Tanzania, United Republic of Tanzania',
    code: 'TZ',
    dialCode: '+255',
    flag: '🇹🇿',
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
    name: 'Timor-Leste',
    code: 'TL',
    dialCode: '+670',
    flag: '🇹🇱',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Togo',
    code: 'TG',
    dialCode: '+228',
    flag: '🇹🇬',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Tokelau',
    code: 'TK',
    dialCode: '+690',
    flag: '🇹🇰',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Tonga',
    code: 'TO',
    dialCode: '+676',
    flag: '🇹🇴',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Trinidad and Tobago',
    code: 'TT',
    dialCode: '+1868',
    flag: '🇹🇹',
    digitCount: 7,
    pattern: '### ####',
  ),
  PhoneCountry(
    name: 'Tunisia',
    code: 'TN',
    dialCode: '+216',
    flag: '🇹🇳',
    digitCount: 10,
    pattern: '### ### ####',
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
    name: 'Turkmenistan',
    code: 'TM',
    dialCode: '+993',
    flag: '🇹🇲',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Turks and Caicos Islands',
    code: 'TC',
    dialCode: '+1649',
    flag: '🇹🇨',
    digitCount: 7,
    pattern: '### ####',
  ),
  PhoneCountry(
    name: 'Tuvalu',
    code: 'TV',
    dialCode: '+688',
    flag: '🇹🇻',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Uganda',
    code: 'UG',
    dialCode: '+256',
    flag: '🇺🇬',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Ukraine',
    code: 'UA',
    dialCode: '+380',
    flag: '🇺🇦',
    digitCount: 10,
    pattern: '### ### ####',
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
    name: 'Uruguay',
    code: 'UY',
    dialCode: '+598',
    flag: '🇺🇾',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Uzbekistan',
    code: 'UZ',
    dialCode: '+998',
    flag: '🇺🇿',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Vanuatu',
    code: 'VU',
    dialCode: '+678',
    flag: '🇻🇺',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Venezuela, Bolivarian Republic of Venezuela',
    code: 'VE',
    dialCode: '+58',
    flag: '🇻🇪',
    digitCount: 10,
    pattern: '### ### ####',
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
    name: 'Virgin Islands, British',
    code: 'VG',
    dialCode: '+1284',
    flag: '🇻🇬',
    digitCount: 7,
    pattern: '### ####',
  ),
  PhoneCountry(
    name: 'Virgin Islands, U.S.',
    code: 'VI',
    dialCode: '+1340',
    flag: '🇻🇮',
    digitCount: 7,
    pattern: '### ####',
  ),
  PhoneCountry(
    name: 'Wallis and Futuna',
    code: 'WF',
    dialCode: '+681',
    flag: '🇼🇫',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Yemen',
    code: 'YE',
    dialCode: '+967',
    flag: '🇾🇪',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Zambia',
    code: 'ZM',
    dialCode: '+260',
    flag: '🇿🇲',
    digitCount: 10,
    pattern: '### ### ####',
  ),
  PhoneCountry(
    name: 'Zimbabwe',
    code: 'ZW',
    dialCode: '+263',
    flag: '🇿🇼',
    digitCount: 10,
    pattern: '### ### ####',
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
