String normalizePaletId(String raw) {
  return raw.replaceAll(' ', '').trim();
}

List<String> parsePaletsFromLines(Iterable<String> rawPalets) {
  return rawPalets
      .map(normalizePaletId)
      .where((value) => value.isNotEmpty)
      .toList();
}
