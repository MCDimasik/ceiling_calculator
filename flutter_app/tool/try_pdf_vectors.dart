import 'dart:io';

import 'package:flutter/widgets.dart';

import 'package:ceiling_calculator/domain/pdf_vector_walls.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dir = Directory(r'C:\Users\noize\Downloads');
  final pdfs = dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.toLowerCase().endsWith('.pdf'))
      .toList()
    ..sort((a, b) => a.lengthSync().compareTo(b.lengthSync()));
  final target = pdfs.firstWhere(
    (f) {
      final n = f.lengthSync();
      return n > 200000 && n < 2000000;
    },
    orElse: () => pdfs.first,
  );
  // ignore: avoid_print
  print('File: ${target.path}');
  final bytes = target.readAsBytesSync();
  final walls = PdfVectorWallExtractor.extract(
    pdfBytes: bytes,
    pageIndex: 1,
    imageSize: const Size(2384, 1684),
  );
  // ignore: avoid_print
  print(
    'segments=${walls?.segments.length} junctions=${walls?.junctions.length} '
    'img=${walls?.imageSize}',
  );
  if (walls == null) return;
  final taps = <Offset>[
    Offset(walls.imageSize.width * 0.25, walls.imageSize.height * 0.30),
    Offset(walls.imageSize.width * 0.50, walls.imageSize.height * 0.50),
    Offset(walls.imageSize.width * 0.70, walls.imageSize.height * 0.40),
    Offset(walls.imageSize.width * 0.35, walls.imageSize.height * 0.60),
  ];
  for (final tap in taps) {
    final face = walls.roomOutlineAt(tap);
    // ignore: avoid_print
    print('tap=$tap → verts=${face?.length}');
  }
}
