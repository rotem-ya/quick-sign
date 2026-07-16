import 'dart:typed_data';

import '../models/library_file.dart';

const bool isSupported = false;

Future<LibraryFolder?> pickFolder() async => null;

Future<List<LibraryFolder>> listFolders() async => const [];

Future<void> removeFolder(String id) async {}

Future<List<LibraryFile>> listFiles(String folderId) async => const [];

Future<Uint8List?> readFile(String fileId) async => null;
