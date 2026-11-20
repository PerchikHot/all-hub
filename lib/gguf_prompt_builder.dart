/// Bounded ChatML prompt for Qwen-style GGUF chat templates.
/// This is an approximation: character limits do not equal token limits.
typedef GgufTurn = ({bool user, String text});

String buildGgufChatPrompt(List<GgufTurn> messages, {
  int maxCharacters = 2600,
  int maxTurns = 8,
}) {
  final selected = <GgufTurn>[];
  var remaining = maxCharacters;
  for (final turn in messages.reversed.take(maxTurns)) {
    if (remaining <= 0) break;
    // Escape ChatML control tokens in untrusted user and model text.
    final safe = turn.text
        .replaceAll('<|', '< |')
        .replaceAll('|>', '| >');
    final clipped = safe.length > remaining
        ? safe.substring(safe.length - remaining)
        : safe;
    selected.insert(0, (user: turn.user, text: clipped));
    remaining -= clipped.length;
  }
  final buffer = StringBuffer(
    '<|im_start|>system\n'
    'Ты Эйра, локальный помощник в All Hub. '
    'Отвечай естественно на русском языке. '
    'Если не знаешь ответа, скажи об этом.\n'
    '<|im_end|>\n',
  );
  for (final turn in selected) {
    buffer.write('<|im_start|>${turn.user ? 'user' : 'assistant'}\n'
        '${turn.text}\n<|im_end|>\n');
  }
  buffer.write('<|im_start|>assistant\n');
  return buffer.toString();
}
