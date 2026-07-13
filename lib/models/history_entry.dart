/// A document kept in the on-device history — persisted until the user
/// explicitly deletes it (not a temp file, not cleared by the OS). Covers
/// two kinds of moments, distinguished by [signed]: every document opened
/// (so it's easy to find again even if never signed) and every document
/// actually signed and sent/exported — opening then signing the same file
/// produces two separate entries, like a timeline.
class HistoryEntry {
  HistoryEntry({
    required this.id,
    required this.fileName,
    required this.savedAt,
    required this.pageCount,
    required this.sizeBytes,
    required this.filePath,
    this.signed = true,
  });

  final String id;
  final String fileName;
  final DateTime savedAt;
  final int pageCount;
  final int sizeBytes;

  /// Absolute path of the PDF in the app's own documents directory.
  final String filePath;

  /// False for an entry recorded when the document was merely opened, not
  /// (yet, or ever) signed and exported.
  final bool signed;

  Map<String, Object?> toJson() => {
    'id': id,
    'fileName': fileName,
    'savedAt': savedAt.toIso8601String(),
    'pageCount': pageCount,
    'sizeBytes': sizeBytes,
    'filePath': filePath,
    'signed': signed,
  };

  /// Returns null on malformed data instead of throwing, so one corrupt
  /// entry can't take the whole history list down.
  static HistoryEntry? fromJson(Map<String, dynamic> json) {
    try {
      return HistoryEntry(
        id: json['id'] as String,
        fileName: json['fileName'] as String,
        savedAt: DateTime.parse(json['savedAt'] as String),
        pageCount: json['pageCount'] as int,
        sizeBytes: json['sizeBytes'] as int,
        filePath: json['filePath'] as String,
        // Older entries predate this field — they were all recorded at
        // the (former) only call site, after signing.
        signed: json['signed'] as bool? ?? true,
      );
    } catch (_) {
      return null;
    }
  }
}
