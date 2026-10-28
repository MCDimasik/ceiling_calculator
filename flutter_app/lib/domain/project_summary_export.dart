import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'documentation_model.dart';
import 'pdf_fonts.dart';
import 'project_dashboard.dart';

String buildProjectSummaryText(ProjectDashboardSummary dash) {
  final p = dash.project;
  final stamp = ProjectDocumentation.fromJson(p.documentationJson).stamp;
  final buf = StringBuffer()
    ..writeln('СВОДКА ПО ОБЪЕКТУ · КОМПЛЕКС ОТДЕЛКИ')
    ..writeln('Объект: ${stamp.objectName.isEmpty ? p.name : stamp.objectName}')
    ..writeln('Дата: ${_fmt(DateTime.now())}')
    ..writeln('')
    ..writeln('Комнат: ${dash.roomCount}')
    ..writeln('Готово к акту: ${dash.readyLabel}')
    ..writeln('Площадь полов: ${dash.totalAreaM2.toStringAsFixed(1)} м²')
    ..writeln('Периметр суммарно: ${dash.totalPerimeterM.toStringAsFixed(1)} м')
    ..writeln(
      'Проектирование: ${dash.designDoneTotal}/${dash.designStepsTotal} · '
      'Скрытые: ${dash.hiddenDoneTotal}/${dash.hiddenStepsTotal}',
    );
  if (dash.urgentCount > 0) {
    buf.writeln('Срочных помещений: ${dash.urgentCount}');
  }
  buf.writeln('');

  if (dash.needsAttention.isEmpty) {
    buf.writeln('Все помещения закрыты или без блокеров.');
  } else {
    buf.writeln('Требуют внимания (${dash.needsAttention.length}):');
    for (final item in dash.needsAttention) {
      final cl = RoomDocumentationChecklist.fromJson(item.room.documentationChecklistJson);
      final assignee = cl.assignee.isEmpty ? '' : ' · ${cl.assignee}';
      final pri = cl.priority == RoomFieldPriority.urgent ? ' [СРОЧНО]' : '';
      buf.writeln(
        '• ${item.room.name}$pri$assignee — ${item.summary.shortLabel}',
      );
      for (final m in item.summary.missingItems.take(4)) {
        buf.writeln('    – $m');
      }
      if (item.summary.missingItems.length > 4) {
        buf.writeln('    … ещё ${item.summary.missingItems.length - 4}');
      }
    }
  }

  buf
    ..writeln('')
    ..writeln('Готовые помещения:');
  final readyRooms = dash.rooms.where((r) => r.isReady).toList();
  if (readyRooms.isEmpty) {
    buf.writeln('  (пока нет)');
  } else {
    for (final item in readyRooms) {
      buf.writeln('  ✓ ${item.room.name}');
    }
  }

  return buf.toString();
}

Future<Uint8List> buildProjectSummaryPdf(ProjectDashboardSummary dash) async {
  final text = buildProjectSummaryText(dash);
  final pdf = await PdfFonts.newDocument();
  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      build: (context) => [
        pw.Text(
          'Сводка объекта · ${dash.project.name}',
          style: PdfFonts.titleStyle(fontSize: 14),
        ),
        pw.SizedBox(height: 10),
        ...text.split('\n').map(
              (line) => pw.Text(
                line.isEmpty ? ' ' : line,
                style: PdfFonts.text(fontSize: 9),
              ),
            ),
      ],
    ),
  );
  return pdf.save();
}

String _fmt(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
