import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

class ReceiptTemplate {
  ReceiptTemplate(this.data);
  final Map<String, dynamic> data;
  String get id => data['id'] as String? ?? '';
  String get name => data['name'] as String? ?? id;
  String? get customParser => data['custom_parser'] as String?;
}

List<ReceiptTemplate>? _cache;

Future<List<ReceiptTemplate>> loadReceiptTemplates({bool force = false}) async {
  if (_cache != null && !force) return _cache!;
  final out = <ReceiptTemplate>[];
  final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
  final paths = manifest
      .listAssets()
      .where((k) =>
          k.startsWith('assets/receipt_templates/') &&
          k.endsWith('.json') &&
          !k.split('/').last.startsWith('_'))
      .toList()
    ..sort();
  for (final path in paths) {
    try {
      final raw = await rootBundle.loadString(path);
      final data = jsonDecode(raw) as Map<String, dynamic>;
      if (data['id'] != null) out.add(ReceiptTemplate(data));
    } catch (_) {}
  }
  _cache = out;
  return out;
}

int scoreTemplate(String text, ReceiptTemplate tpl) {
  final detect = (tpl.data['detect'] as Map?)?.cast<String, dynamic>() ?? {};
  var score = 0;
  final textLow = text.toLowerCase();
  for (final phrase in (detect['any_contains'] as List? ?? [])) {
    if (textLow.contains(phrase.toString().toLowerCase())) {
      score += (detect['weight_contains'] as num?)?.toInt() ?? 2;
    }
  }
  for (final phrase in (detect['all_contains'] as List? ?? [])) {
    if (textLow.contains(phrase.toString().toLowerCase())) {
      score += (detect['weight_all'] as num?)?.toInt() ?? 3;
    } else {
      return 0;
    }
  }
  for (final pattern in (detect['regex'] as List? ?? [])) {
    if (RegExp(pattern.toString(), caseSensitive: false, multiLine: true).hasMatch(text)) {
      score += (detect['weight_regex'] as num?)?.toInt() ?? 2;
    }
  }
  return score;
}

(ReceiptTemplate? tpl, int score) detectTemplate(String text, List<ReceiptTemplate> templates) {
  ReceiptTemplate? best;
  var bestScore = 0;
  for (final tpl in templates) {
    final s = scoreTemplate(text, tpl);
    final minScore = ((tpl.data['detect'] as Map?)?['min_score'] as num?)?.toInt() ?? 2;
    if (s >= minScore && s > bestScore) {
      bestScore = s;
      best = tpl;
    }
  }
  return (best, bestScore);
}

/// PDF text extraction: decompress FlateDecode streams + collect literal strings.
/// Better than ASCII-only scrape; still not a full PDF parser (Kivy uses pypdf).
String extractPdfTextRough(List<int> bytes) {
  final buf = StringBuffer();
  final seen = <String>{};

  void addLine(String s) {
    final t = s.trim();
    if (t.isEmpty || t.length > 500) return;
    if (seen.add(t)) buf.writeln(t);
  }

  void harvest(String raw) {
    for (final m in RegExp(r'\((?:\\.|[^\\)])*\)').allMatches(raw)) {
      var s = m.group(0)!;
      s = s.substring(1, s.length - 1);
      s = s
          .replaceAll(r'\n', '\n')
          .replaceAll(r'\r', '\r')
          .replaceAll(r'\t', '\t')
          .replaceAll(r'\(', '(')
          .replaceAll(r'\)', ')')
          .replaceAll(r'\\', r'\');
      // Octal escapes \ddd
      s = s.replaceAllMapped(RegExp(r'\\([0-7]{1,3})'), (m) {
        return String.fromCharCode(int.parse(m.group(1)!, radix: 8));
      });
      addLine(s);
    }
    // TJ arrays: [(Hello) -10 (World)] TJ
    for (final m in RegExp(r'\[(.*?)\]\s*TJ', dotAll: true).allMatches(raw)) {
      for (final sm in RegExp(r'\((?:\\.|[^\\)])*\)').allMatches(m.group(1)!)) {
        var s = sm.group(0)!;
        s = s.substring(1, s.length - 1).replaceAll(r'\(', '(').replaceAll(r'\)', ')');
        addLine(s);
      }
    }
    for (final line in raw.split(RegExp(r'[\r\n]+'))) {
      if (RegExp(r'\d').hasMatch(line) && line.length < 200) addLine(line);
    }
  }

  // Uncompressed body (ASCII layer).
  final ascii = String.fromCharCodes(
    bytes.where((b) => (b >= 32 && b < 127) || b == 10 || b == 13),
  );
  harvest(ascii);

  // Inflate FlateDecode streams (common in real PDFs).
  final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
  var offset = 0;
  final rawStr = String.fromCharCodes(bytes.map((b) => b < 128 ? b : 32));
  while (true) {
    final i = rawStr.indexOf('stream', offset);
    if (i < 0) break;
    // Skip keyword false-positives like "endstream"
    if (i > 0 && RegExp(r'[A-Za-z]').hasMatch(rawStr[i - 1])) {
      offset = i + 6;
      continue;
    }
    var contentStart = i + 'stream'.length;
    if (contentStart < bytes.length && bytes[contentStart] == 13) contentStart++;
    if (contentStart < bytes.length && bytes[contentStart] == 10) contentStart++;
    final end = rawStr.indexOf('endstream', contentStart);
    if (end < 0) break;
    var contentEnd = end;
    if (contentEnd > 0 && bytes[contentEnd - 1] == 10) contentEnd--;
    if (contentEnd > 0 && bytes[contentEnd - 1] == 13) contentEnd--;
    if (contentEnd > contentStart && contentEnd - contentStart < 8 * 1024 * 1024) {
      final chunk = data.sublist(contentStart, contentEnd);
      try {
        final inflated = ZLibCodec(raw: true).decode(chunk);
        harvest(utf8.decode(inflated, allowMalformed: true));
      } catch (_) {
        try {
          final inflated = ZLibCodec().decode(chunk);
          harvest(utf8.decode(inflated, allowMalformed: true));
        } catch (_) {
          harvest(String.fromCharCodes(chunk.where((b) => b >= 32 && b < 127)));
        }
      }
    }
    offset = end + 9;
  }

  return buf.toString();
}

