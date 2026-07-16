import 'package:flutter_test/flutter_test.dart';

import 'package:quick_sign/models/library_file.dart';

LibraryFile _file(
  String name, {
  int sizeBytes = 100,
  DateTime? modified,
  String folderId = 'f1',
}) {
  return LibraryFile(
    id: name,
    folderId: folderId,
    name: name,
    sizeBytes: sizeBytes,
    modified: modified ?? DateTime(2026, 1, 1),
  );
}

void main() {
  group('LibraryFile.kind', () {
    test('recognizes pdf by extension, case-insensitively', () {
      expect(_file('doc.pdf').kind, LibraryFileKind.pdf);
      expect(_file('doc.PDF').kind, LibraryFileKind.pdf);
    });

    test('recognizes common image extensions', () {
      for (final ext in ['png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp', 'heic']) {
        expect(_file('photo.$ext').kind, LibraryFileKind.image, reason: ext);
      }
    });

    test('falls back to other for unknown extensions', () {
      expect(_file('notes.txt').kind, LibraryFileKind.other);
      expect(_file('noextension').kind, LibraryFileKind.other);
    });
  });

  group('applyLibraryFilterAndSort', () {
    final files = [
      _file('b.pdf', sizeBytes: 300, modified: DateTime(2026, 1, 3)),
      _file('a.png', sizeBytes: 100, modified: DateTime(2026, 1, 1)),
      _file('c.pdf', sizeBytes: 200, modified: DateTime(2026, 1, 2)),
    ];

    test('null filter keeps every file', () {
      final result = applyLibraryFilterAndSort(
        files,
        null,
        const LibrarySort(LibrarySortField.name),
      );
      expect(result.length, 3);
    });

    test('filters by kind', () {
      final result = applyLibraryFilterAndSort(
        files,
        LibraryFileKind.pdf,
        const LibrarySort(LibrarySortField.name),
      );
      expect(result.map((f) => f.name), ['b.pdf', 'c.pdf']);
    });

    test('sorts by name ascending, case-insensitively', () {
      final result = applyLibraryFilterAndSort(
        files,
        null,
        const LibrarySort(LibrarySortField.name),
      );
      expect(result.map((f) => f.name), ['a.png', 'b.pdf', 'c.pdf']);
    });

    test('sorts by modified date, newest last when ascending', () {
      final result = applyLibraryFilterAndSort(
        files,
        null,
        const LibrarySort(LibrarySortField.modified),
      );
      expect(result.map((f) => f.name), ['a.png', 'c.pdf', 'b.pdf']);
    });

    test('sorts by size descending when toggled', () {
      const sort = LibrarySort(LibrarySortField.size, ascending: false);
      final result = applyLibraryFilterAndSort(files, null, sort);
      expect(result.map((f) => f.name), ['b.pdf', 'c.pdf', 'a.png']);
    });
  });

  group('LibrarySort.toggledOn', () {
    test('switching to a new field resets to ascending', () {
      const sort = LibrarySort(LibrarySortField.name, ascending: false);
      final next = sort.toggledOn(LibrarySortField.size);
      expect(next.field, LibrarySortField.size);
      expect(next.ascending, isTrue);
    });

    test('re-selecting the same field flips direction', () {
      const sort = LibrarySort(LibrarySortField.name);
      final next = sort.toggledOn(LibrarySortField.name);
      expect(next.field, LibrarySortField.name);
      expect(next.ascending, isFalse);
    });
  });
}
