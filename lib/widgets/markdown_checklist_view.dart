import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;

class MarkdownChecklistView extends StatelessWidget {
  final String content;
  final void Function(int lineIndex, bool checked)? onToggleChecklist;

  const MarkdownChecklistView({
    super.key,
    required this.content,
    this.onToggleChecklist,
  });

  static final RegExp _taskLineRegex = RegExp(
    r'^(\s*(?:[-*+]\s+)?)\[( |x|X)\]\s*(.*)$',
  );

  /// Toggles checklist state on [lineIndex] of [rawText] cleanly.
  static String toggleTaskAtLine(String rawText, int lineIndex, bool checked) {
    final lines = rawText.split('\n');
    if (lineIndex < 0 || lineIndex >= lines.length) return rawText;
    final match = _taskLineRegex.firstMatch(lines[lineIndex]);
    if (match == null) return rawText;
    final prefix = match.group(1) ?? '- ';
    final body = match.group(3) ?? '';
    lines[lineIndex] = '$prefix[${checked ? 'x' : ' '}] $body';
    return lines.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (content.trim().isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          'Önizlenecek içerik yok.',
          style: TextStyle(color: theme.hintColor),
        ),
      );
    }

    final lines = content.split('\n');
    final List<Widget> widgets = [];
    final List<String> markdownBuffer = [];

    void flushMarkdownBuffer() {
      if (markdownBuffer.isEmpty) return;
      final blockText = markdownBuffer.join('\n');
      markdownBuffer.clear();
      if (blockText.trim().isEmpty) return;

      final doc = md.Document(extensionSet: md.ExtensionSet.gitHubFlavored);
      final nodes = doc.parseLines(blockText.split('\n'));
      for (final node in nodes) {
        widgets.add(_buildBlockNode(context, node));
      }
    }

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final taskMatch = _taskLineRegex.firstMatch(line);
      if (taskMatch != null) {
        flushMarkdownBuffer();
        final checked = (taskMatch.group(2) ?? ' ').toLowerCase() == 'x';
        final label = taskMatch.group(3) ?? '';
        final lineIdx = i;
        widgets.add(
          InkWell(
            onTap: onToggleChecklist == null
                ? null
                : () => onToggleChecklist!(lineIdx, !checked),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: checked,
                      onChanged: onToggleChecklist == null
                          ? null
                          : (val) =>
                              onToggleChecklist!(lineIdx, val ?? !checked),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        label,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          decoration:
                              checked ? TextDecoration.lineThrough : null,
                          color: checked ? theme.hintColor : null,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      } else {
        markdownBuffer.add(line);
      }
    }
    flushMarkdownBuffer();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: widgets,
    );
  }

  Widget _buildBlockNode(BuildContext context, md.Node node) {
    final theme = Theme.of(context);
    if (node is md.Text) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Text(node.text, style: theme.textTheme.bodyMedium),
      );
    }
    if (node is! md.Element) {
      return const SizedBox.shrink();
    }

    switch (node.tag) {
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        final level = int.tryParse(node.tag.substring(1)) ?? 3;
        final sizes = <int, double>{1: 24, 2: 20, 3: 17, 4: 15, 5: 14, 6: 13};
        return Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 4),
          child: Text.rich(
            TextSpan(
              children: _buildInlineSpans(context, node.children ?? const []),
              style: theme.textTheme.titleLarge?.copyWith(
                fontSize: sizes[level] ?? 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );
      case 'p':
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text.rich(
            TextSpan(
              children: _buildInlineSpans(context, node.children ?? const []),
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
            ),
          ),
        );
      case 'pre':
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.75,
            ),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.25),
            ),
          ),
          child: SelectableText(
            node.textContent.trimRight(),
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              height: 1.4,
            ),
          ),
        );
      case 'blockquote':
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: theme.colorScheme.primary, width: 3),
            ),
            color: theme.colorScheme.primary.withValues(alpha: 0.06),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: (node.children ?? const [])
                .map((c) => _buildBlockNode(context, c))
                .toList(),
          ),
        );
      case 'ul':
      case 'ol':
        final items = (node.children ?? const []).whereType<md.Element>().toList();
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: List.generate(items.length, (idx) {
              final marker = node.tag == 'ol' ? '${idx + 1}.' : '•';
              final item = items[idx];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 22,
                      child: Text(
                        marker,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: _buildInlineSpans(
                            context,
                            item.children ?? const [],
                          ),
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
        );
      case 'hr':
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Divider(),
        );
      default:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text.rich(
            TextSpan(
              children: _buildInlineSpans(context, node.children ?? const []),
              style: theme.textTheme.bodyMedium,
            ),
          ),
        );
    }
  }

  List<InlineSpan> _buildInlineSpans(
    BuildContext context,
    List<md.Node> nodes, {
    TextStyle? inheritedStyle,
  }) {
    final theme = Theme.of(context);
    final List<InlineSpan> spans = [];

    for (final node in nodes) {
      if (node is md.Text) {
        spans.add(TextSpan(text: node.text, style: inheritedStyle));
      } else if (node is md.Element) {
        TextStyle style = inheritedStyle ?? const TextStyle();
        switch (node.tag) {
          case 'strong':
            style = style.copyWith(fontWeight: FontWeight.bold);
            spans.addAll(
              _buildInlineSpans(
                context,
                node.children ?? const [],
                inheritedStyle: style,
              ),
            );
            break;
          case 'em':
            style = style.copyWith(fontStyle: FontStyle.italic);
            spans.addAll(
              _buildInlineSpans(
                context,
                node.children ?? const [],
                inheritedStyle: style,
              ),
            );
            break;
          case 'del':
            style = style.copyWith(decoration: TextDecoration.lineThrough);
            spans.addAll(
              _buildInlineSpans(
                context,
                node.children ?? const [],
                inheritedStyle: style,
              ),
            );
            break;
          case 'code':
            spans.add(
              TextSpan(
                text: node.textContent,
                style: style.copyWith(
                  fontFamily: 'monospace',
                  backgroundColor:
                      theme.colorScheme.surfaceContainerHighest,
                ),
              ),
            );
            break;
          case 'a':
            spans.addAll(
              _buildInlineSpans(
                context,
                node.children ?? const [],
                inheritedStyle: style.copyWith(
                  color: theme.colorScheme.primary,
                  decoration: TextDecoration.underline,
                ),
              ),
            );
            break;
          case 'br':
            spans.add(const TextSpan(text: '\n'));
            break;
          default:
            spans.addAll(
              _buildInlineSpans(
                context,
                node.children ?? const [],
                inheritedStyle: style,
              ),
            );
            break;
        }
      }
    }
    return spans;
  }
}
