class CachedDropboxFolder {
  final String id;             // Dropbox file ID is stable across renames
  final String name;
  final String pathLower;      // e.g. "/researchobs/griffin"
  final DateTime fetchedAt;
  final List<CachedDropboxFolder> children; // keep shallow (e.g., 2 levels)

  CachedDropboxFolder({
    required this.id,
    required this.name,
    required this.pathLower,
    required this.fetchedAt,
    this.children = const [],
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'pathLower': pathLower,
    'fetchedAt': fetchedAt.toIso8601String(),
    'children': children.map((c) => c.toJson()).toList(),
  };

  factory CachedDropboxFolder.fromJson(Map<String, dynamic> j) => CachedDropboxFolder(
    id: j['id'],
    name: j['name'],
    pathLower: j['pathLower'],
    fetchedAt: DateTime.parse(j['fetchedAt']),
    children: (j['children'] as List? ?? [])
        .map((c) => CachedDropboxFolder.fromJson(Map<String, dynamic>.from(c)))
        .toList(),
  );
}

enum UploadStatus { pending, uploading, done, failed }

class UploadJob {
  final String localFilePath;
  final String fileName;
  final String dropboxFolderId;   // prefer ID-based targeting
  final String? pathLowerFallback; // fallback if ID lookup fails
  UploadStatus status;
  int retries;
  final DateTime createdAt;

  UploadJob({
    required this.localFilePath,
    required this.fileName,
    required this.dropboxFolderId,
    this.pathLowerFallback,
    this.status = UploadStatus.pending,
    this.retries = 0,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'localFilePath': localFilePath,
    'fileName': fileName,
    'dropboxFolderId': dropboxFolderId,
    'pathLowerFallback': pathLowerFallback,
    'status': status.name,
    'retries': retries,
    'createdAt': createdAt.toIso8601String(),
  };

  factory UploadJob.fromJson(Map<String, dynamic> j) => UploadJob(
    localFilePath: j['localFilePath'],
    fileName: j['fileName'],
    dropboxFolderId: j['dropboxFolderId'],
    pathLowerFallback: j['pathLowerFallback'],
    status: UploadStatus.values.firstWhere((e) => e.name == j['status'], orElse: () => UploadStatus.pending),
    retries: j['retries'] ?? 0,
    createdAt: DateTime.parse(j['createdAt']),
  );
}
