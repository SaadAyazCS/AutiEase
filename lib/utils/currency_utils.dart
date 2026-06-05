/// Formats a double price into standard PKR currency format (e.g. 1000.0 -> "Rs. 1,000 PKR").
String formatPrice(double price) {
  final isInt = price % 1 == 0;
  final numStr = isInt ? price.toInt().toString() : price.toStringAsFixed(2);
  final RegExp reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
  final parts = numStr.split('.');
  parts[0] = parts[0].replaceAllMapped(reg, (Match match) => '${match.group(1)},');
  return 'Rs. ${parts.join('.')} PKR';
}

String formatPriceString(String raw) {
  if (raw.isEmpty) return '';
  final regex = RegExp(r'(\d+[.,]?\d*)');
  final match = regex.firstMatch(raw);
  if (match == null) {
    return raw;
  }
  
  final numStr = match.group(1)!;
  final value = double.tryParse(numStr.replaceAll(',', '')) ?? 0.0;
  
  final isInt = value % 1 == 0;
  final formattedNumStr = isInt ? value.toInt().toString() : value.toStringAsFixed(2);
  
  final RegExp commaRegex = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
  final parts = formattedNumStr.split('.');
  parts[0] = parts[0].replaceAllMapped(commaRegex, (Match m) => '${m.group(1)},');
  
  return 'Rs. ${parts.join('.')} PKR';
}
