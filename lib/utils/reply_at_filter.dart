/// 只过滤由已知@用户名组成的正文，普通文字、未知用户名和空白正文都不匹配。
bool isMentionOnlyReply(
  String message,
  Iterable<String> names, {
  bool hasReplyPrefix = false,
}) {
  if (hasReplyPrefix) {
    final colon = message.indexOf(':');
    if (colon < 0) return false;
    message = message.substring(colon + 1);
  }
  final mentions =
      names.where((name) => name.isNotEmpty).map((name) => '@$name').toList()
        ..sort((a, b) => b.length.compareTo(a.length));
  var position = 0;
  var found = false;
  bool whitespace(int index) => message[index].trim().isEmpty;
  while (position < message.length) {
    if (whitespace(position)) {
      position++;
      continue;
    }
    String? match;
    for (final mention in mentions) {
      if (!message.startsWith(mention, position)) continue;
      final end = position + mention.length;
      if (end == message.length || whitespace(end) || message[end] == '@') {
        match = mention;
        break;
      }
    }
    if (match == null) return false;
    position += match.length;
    found = true;
  }
  return found;
}
