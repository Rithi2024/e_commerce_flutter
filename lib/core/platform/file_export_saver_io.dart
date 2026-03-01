import 'dart:io';

import 'package:path_provider/path_provider.dart';

Future<String> saveExportedFile(List<int> bytes, String fileName) async {
  Directory? dir;
  try {
    dir = await getDownloadsDirectory();
  } catch (_) {
    dir = null;
  }

  dir ??= await getApplicationDocumentsDirectory();
  final path = '${dir.path}${Platform.pathSeparator}$fileName';
  final file = File(path);
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}
