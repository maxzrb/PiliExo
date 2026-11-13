abstract final class FollowedUpSearch {
  static String _normalize(String value) {
    return value.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
  }

  static int? _scoreToken(String token, String candidate) {
    if (candidate == token) return 4000;
    if (candidate.startsWith(token)) return 3000 - candidate.length;

    final containsIndex = candidate.indexOf(token);
    if (containsIndex >= 0) {
      return 2000 - containsIndex * 3 - candidate.length;
    }

    final queryRunes = token.runes.toList();
    final candidateRunes = candidate.runes.toList();
    var queryIndex = 0;
    var firstMatch = -1;
    var lastMatch = -1;
    var gapCount = 0;
    for (
      var i = 0;
      i < candidateRunes.length && queryIndex < queryRunes.length;
      i++
    ) {
      if (candidateRunes[i] == queryRunes[queryIndex]) {
        if (firstMatch == -1) firstMatch = i;
        if (lastMatch != -1 && i - lastMatch > 1) {
          gapCount += i - lastMatch - 1;
        }
        lastMatch = i;
        queryIndex++;
      }
    }
    if (queryIndex != queryRunes.length) return null;

    final span = lastMatch - firstMatch + 1;
    return 1000 -
        gapCount * 10 -
        (span - queryRunes.length) * 2 -
        candidateRunes.length;
  }

  static int? score(String query, String candidate) {
    final normalizedQuery = _normalize(query);
    if (normalizedQuery.isEmpty) return 0;
    final normalizedCandidate = _normalize(candidate);
    if (normalizedCandidate.isEmpty) return null;

    var total = 0;
    for (final token in normalizedQuery.split(' ')) {
      final tokenScore = _scoreToken(token, normalizedCandidate);
      if (tokenScore == null) return null;
      total += tokenScore;
    }
    return total;
  }

  static List<T> filter<T>({
    required Iterable<T> items,
    required String query,
    required String Function(T item) nameOf,
  }) {
    final normalizedQuery = _normalize(query);
    if (normalizedQuery.isEmpty) return items.toList();

    final matches = <({T item, int score, int index})>[];
    var index = 0;
    for (final item in items) {
      final matchScore = score(normalizedQuery, nameOf(item));
      if (matchScore != null) {
        matches.add((item: item, score: matchScore, index: index));
      }
      index++;
    }
    matches.sort((a, b) {
      final scoreCompare = b.score.compareTo(a.score);
      return scoreCompare != 0 ? scoreCompare : a.index.compareTo(b.index);
    });
    return matches.map((match) => match.item).toList();
  }
}
