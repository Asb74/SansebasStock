String buildStockDocId(String paletId) {
  final trimmed = paletId.trim();
  if (RegExp(r'^[123]\d{10}$').hasMatch(trimmed)) {
    return trimmed;
  }

  return '1$trimmed';
}
