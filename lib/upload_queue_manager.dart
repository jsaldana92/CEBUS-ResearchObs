import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'offline_cache_service.dart';
import 'upload_models.dart';
import 'dropbox_upload_service.dart';
import 'dropbox_oauth_service.dart';

class UploadQueueManager {
  UploadQueueManager._();
  static final UploadQueueManager I = UploadQueueManager._();

  final _controller = StreamController<List<UploadJob>>.broadcast();
  StreamSubscription<List<ConnectivityResult>>? _connSub;
  Timer? _retryTimer;

  bool _isProcessing = false;
  bool _inited = false;

  Stream<List<UploadJob>> get jobsStream => _controller.stream;

  Future<void> init() async {
    if (_inited) return;
    _inited = true;

    // Connectivity listener (v6 returns List<ConnectivityResult>)
    _connSub = Connectivity().onConnectivityChanged.listen((results) async {
      debugPrint('[UQM] connectivity change: $results');
      final hasAny = results.any((r) => r != ConnectivityResult.none);
      if (hasAny) {
        unawaited(_tryProcessQueue());
      }
    });

    // Periodic safety retry
    _retryTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(_tryProcessQueue());
    });

    // Try once on startup
    unawaited(_tryProcessQueue());
  }

  Future<void> dispose() async {
    await _connSub?.cancel();
    _retryTimer?.cancel();
    await _controller.close();
    _inited = false;
  }

  Future<void> enqueue(UploadJob job) async {
    final queue = await OfflineCacheService.loadQueue();
    queue.add(job);
    await OfflineCacheService.saveQueue(queue);
    _controller.add(queue);
    debugPrint('[UQM] enqueue: ${job.fileName} -> ${job.pathLowerFallback}');
    unawaited(_tryProcessQueue()); // immediate attempt if online
  }

  Future<void> _tryProcessQueue() async {
    if (_isProcessing) return;

    // v6: checkConnectivity() => List<ConnectivityResult>
    final results = await Connectivity().checkConnectivity();
    final hasAnyNet = results.any((r) => r != ConnectivityResult.none);
    if (!hasAnyNet) return;

    // Stronger reachability check
    if (!await _hasInternet()) {
      debugPrint('[UQM] DNS lookup failed; deferring.');
      return;
    }

    _isProcessing = true;
    try {
      var queue = await OfflineCacheService.loadQueue();
      if (queue.isEmpty) return;

      final auth = await DropboxOAuthService.authStateSnapshot();
      debugPrint('[UQM][auth] has_refresh=${auth['has_refresh']} has_access=${auth['has_access']} '
          'expires_present=${auth['expires_at_ms_present']} ms_remaining=${auth['ms_remaining']} '
          'needs_refresh=${auth['needs_refresh']}');



      for (var i = 0; i < queue.length; i++) {
        var job = queue[i];
        if (job.status == UploadStatus.done) continue;

        // Skip if file is gone
        if (!File(job.localFilePath).existsSync()) {
          debugPrint('[UQM] missing local file: ${job.localFilePath}');
          job.status = UploadStatus.failed;
          queue[i] = job;
          await OfflineCacheService.saveQueue(queue);
          _controller.add(queue);
          continue;
        }

        job.status = UploadStatus.uploading;
        queue[i] = job;
        await OfflineCacheService.saveQueue(queue);
        _controller.add(queue);
        debugPrint('[UQM] uploading: ${job.fileName}');

        try {
          final targetPath = await DropboxUploadService.resolveFolderPath(
            folderId: job.dropboxFolderId,
            pathLowerFallback: job.pathLowerFallback,
          );

          final normalizedPath =
          targetPath.startsWith('/') ? targetPath : '/$targetPath';

          await DropboxUploadService.uploadFileChunkedWithValidToken(
            localFilePath: job.localFilePath,
            dropboxDestPath: '$normalizedPath/${job.fileName}',
          );

          job.status = UploadStatus.done;
          job.retries = 0;
          debugPrint('[UQM] done: ${job.fileName}');
        } catch (e) {
          job.retries += 1;
          job.status =
          job.retries > 5 ? UploadStatus.failed : UploadStatus.pending;
          debugPrint('[UQM] upload error (try ${job.retries}): ${job.fileName} -> $e');

          if (job.status != UploadStatus.failed) {
            await Future.delayed(Duration(seconds: 2 * job.retries));
          }
        } finally {
          queue[i] = job;
          await OfflineCacheService.saveQueue(queue);
          _controller.add(queue);
        }
      }
    } finally {
      _isProcessing = false;
    }
  }

  Future<bool> _hasInternet() async {
    try {
      final result = await InternetAddress.lookup('api.dropboxapi.com')
          .timeout(const Duration(seconds: 3));
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}

// Tiny helper to silence unawaited warnings.
void unawaited(Future<void> f) {}
