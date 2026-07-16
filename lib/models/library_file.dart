/// A folder the user has explicitly picked to browse — Android: a Storage
/// Access Framework tree URI (works for local storage and, via the same
/// mechanism, folders inside Drive/OneDrive/Dropbox). Web: a File System
/// Access API directory handle, kept in memory for the current session.
class LibraryFolder {
  const LibraryFolder({required this.id, required this.name});

  final String id;
  final String name;
}

enum LibraryFileKind { pdf, image, other }

class LibraryFile {
  const LibraryFile({
    required this.id,
    required this.folderId,
    required this.name,
    required this.sizeBytes,
    required this.modified,
  });

  final String id;
  final String folderId;
  final String name;
  final int sizeBytes;
  final DateTime modified;

  static const _imageExtensions = {
    'png',
    'jpg',
    'jpeg',
    'webp',
    'gif',
    'bmp',
    'heic',
  };

  LibraryFileKind get kind {
    final dot = name.lastIndexOf('.');
    final ext = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
    if (ext == 'pdf') return LibraryFileKind.pdf;
    if (_imageExtensions.contains(ext)) return LibraryFileKind.image;
    return LibraryFileKind.other;
  }
}

enum LibrarySortField { name, modified, size }

class LibrarySort {
  const LibrarySort(this.field, {this.ascending = true});

  final LibrarySortField field;
  final bool ascending;

  LibrarySort toggledOn(LibrarySortField newField) {
    if (newField != field) return LibrarySort(newField, ascending: true);
    return LibrarySort(field, ascending: !ascending);
  }

  int compare(LibraryFile a, LibraryFile b) {
    final result = switch (field) {
      LibrarySortField.name =>
        a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      LibrarySortField.modified => a.modified.compareTo(b.modified),
      LibrarySortField.size => a.sizeBytes.compareTo(b.sizeBytes),
    };
    return ascending ? result : -result;
  }
}

/// Filters and sorts in one place so the screen and its tests share exactly
/// the same rules.
List<LibraryFile> applyLibraryFilterAndSort(
  List<LibraryFile> files,
  LibraryFileKind? filter,
  LibrarySort sort,
) {
  final filtered = filter == null
      ? files.toList()
      : files.where((f) => f.kind == filter).toList();
  filtered.sort(sort.compare);
  return filtered;
}
