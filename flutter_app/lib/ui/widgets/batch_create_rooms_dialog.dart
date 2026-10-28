import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'numeric_input.dart';

class BatchRoomDraft {
  BatchRoomDraft({
    this.name = '',
    this.lengthM = '',
    this.widthM = '',
  });

  String name;
  String lengthM;
  String widthM;
}

/// Dialog: create many rectangular rooms at once (length × width in meters).
class BatchCreateRoomsDialog extends StatefulWidget {
  const BatchCreateRoomsDialog({super.key, this.existingRoomCount = 0});

  final int existingRoomCount;

  @override
  State<BatchCreateRoomsDialog> createState() => _BatchCreateRoomsDialogState();
}

class _BatchCreateRoomsDialogState extends State<BatchCreateRoomsDialog> {
  bool _autoNames = false;
  final _rows = <_RowControllers>[];

  @override
  void initState() {
    super.initState();
    _addRow();
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  void _addRow() {
    final row = _RowControllers();
    row.length.addListener(_onChanged);
    row.width.addListener(_onChanged);
    row.name.addListener(_onChanged);
    row.count.addListener(_onChanged);
    _rows.add(row);
  }

  bool _rowHasDimensions(_RowControllers row) =>
      _parseM(row.length.text) != null && _parseM(row.width.text) != null;

  bool _rowComplete(_RowControllers row) {
    if (!_rowHasDimensions(row)) return false;
    if (_autoNames) return true;
    return row.name.text.trim().isNotEmpty;
  }

  void _ensureTrailingRow() {
    if (_rows.isEmpty) {
      _addRow();
      return;
    }
    if (_rowComplete(_rows.last)) {
      _addRow();
    }
  }

  void _onChanged() {
    if (_rows.isEmpty) return;
    setState(_ensureTrailingRow);
  }

  void _setAutoNames(bool value) {
    setState(() {
      _autoNames = value;
      _ensureTrailingRow();
    });
  }

  static double? _parseM(String raw) {
    final t = raw.trim().replaceAll(',', '.');
    if (t.isEmpty) return null;
    final v = double.tryParse(t);
    if (v == null || v <= 0) return null;
    return v;
  }

  static int _parseCount(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return 1;
    final v = int.tryParse(t);
    if (v == null || v < 1) return 1;
    return v;
  }

  List<({String name, double lengthCm, double widthCm})> _collect() {
    final out = <({String name, double lengthCm, double widthCm})>[];
    var autoIndex = 0;
    for (final row in _rows) {
      final len = _parseM(row.length.text);
      final wid = _parseM(row.width.text);
      if (len == null || wid == null) continue;
      if (_autoNames) {
        final n = _parseCount(row.count.text);
        for (var k = 0; k < n; k++) {
          autoIndex++;
          out.add((
            name: 'Комната ${widget.existingRoomCount + autoIndex}',
            lengthCm: len * 100,
            widthCm: wid * 100,
          ));
        }
      } else {
        final name = row.name.text.trim();
        if (name.isEmpty) continue;
        out.add((name: name, lengthCm: len * 100, widthCm: wid * 100));
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ready = _collect();

    return AlertDialog(
      title: const Text('Несколько помещений'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Автоназвания'),
              subtitle: Text(
                _autoNames
                    ? 'Имена по порядку: Комната ${widget.existingRoomCount + 1}… '
                        'В строке — количество одинаковых'
                    : 'Задайте название для каждой строки',
                style: theme.textTheme.bodySmall,
              ),
              value: _autoNames,
              onChanged: _setAutoNames,
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.45,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _rows.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final row = _rows[i];
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: SizedBox(
                          width: 28,
                          child: Text(
                            '${i + 1}.',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: row.length,
                          keyboardType: NumericInput.decimalKeyboard,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[\d.,]'),
                            ),
                          ],
                          decoration: const InputDecoration(
                            labelText: 'Длина, м',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: row.width,
                          keyboardType: NumericInput.decimalKeyboard,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[\d.,]'),
                            ),
                          ],
                          decoration: const InputDecoration(
                            labelText: 'Ширина, м',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 3,
                        child: _autoNames
                            ? TextField(
                                controller: row.count,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                decoration: const InputDecoration(
                                  labelText: 'Кол-во',
                                  hintText: '1',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              )
                            : TextField(
                                controller: row.name,
                                keyboardType: NumericInput.textKeyboard,
                                textCapitalization: TextCapitalization.sentences,
                                decoration: InputDecoration(
                                  labelText: 'Название',
                                  border: const OutlineInputBorder(),
                                  isDense: true,
                                  hintText:
                                      'Комната ${widget.existingRoomCount + i + 1}',
                                ),
                              ),
                      ),
                      if (_rows.length > 1)
                        IconButton(
                          tooltip: 'Удалить строку',
                          onPressed: () {
                            setState(() {
                              final removed = _rows.removeAt(i);
                              removed.dispose();
                              if (_rows.isEmpty) _addRow();
                              _ensureTrailingRow();
                            });
                          },
                          icon: const Icon(Icons.close),
                        ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _autoNames
                  ? 'Пустое «Кол-во» = 1 комната. Несколько строк — разные размеры.'
                  : 'Размеры в метрах. Будут созданы прямоугольные чертежи.',
              style: theme.textTheme.bodySmall,
            ),
            if (ready.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'К созданию: ${ready.length}',
                  style: theme.textTheme.labelLarge,
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: ready.isEmpty ? null : () => Navigator.pop(context, ready),
          child: const Text('Создать'),
        ),
      ],
    );
  }
}

class _RowControllers {
  final length = TextEditingController();
  final width = TextEditingController();
  final name = TextEditingController();
  final count = TextEditingController();

  void dispose() {
    length.dispose();
    width.dispose();
    name.dispose();
    count.dispose();
  }
}
