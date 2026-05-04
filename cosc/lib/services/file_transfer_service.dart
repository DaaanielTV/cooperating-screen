import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:crypto/crypto.dart';
import 'data_channel_service.dart';
import 'package:uuid/uuid.dart';

class FileTransferProgress {
  final String transferId;
  final String fileName;
  final int totalBytes;
  int transferredBytes = 0;
  int chunksReceived = 0;
  int totalChunks = 0;
  DateTime startTime = DateTime.now();
  DateTime? lastUpdateTime;
  String? error;

  FileTransferProgress({
    required this.transferId,
    required this.fileName,
    required this.totalBytes,
    required this.totalChunks,
  });

  double get progress => totalBytes > 0 ? transferredBytes / totalBytes : 0.0;

  Duration get elapsedTime => DateTime.now().difference(startTime);

  int get bytesPerSecond {
    final seconds = elapsedTime.inSeconds;
    return seconds > 0 ? (transferredBytes ~/ seconds) : 0;
  }

  Duration get estimatedTimeRemaining {
    if (bytesPerSecond == 0) return Duration.zero;
    final remainingBytes = totalBytes - transferredBytes;
    final seconds = remainingBytes ~/ bytesPerSecond;
    return Duration(seconds: seconds);
  }

  void updateTransferred(int bytes) {
    transferredBytes += bytes;
    lastUpdateTime = DateTime.now();
  }

  void updateChunksReceived(int count) {
    chunksReceived += count;
  }
}

class FileTransferService {
  final DataChannelService dataChannelService;
  final String? allowedSaveDirectory;
  
  static const int chunkSize = 16384; // 16KB chunks
  static const int maxConcurrentTransfers = 3;
  static const int maxInboundFileSizeBytes = 100 * 1024 * 1024; // 100MB
  static const int maxChunksPerTransfer = 7000;
  
  final _activeTransfers = <String, FileTransferProgress>{};
  final _receivedChunks = <String, Map<int, Uint8List>>{};
  
  // Callbacks
  Function(FileTransferProgress)? onProgressUpdate;
  Function(String, String)? onTransferComplete;
  Function(String, String)? onTransferError;

  FileTransferService({
    required this.dataChannelService,
    this.allowedSaveDirectory,
  });

  /// Start sending a file
  Future<String?> sendFile({
    required File file,
    required String remoteDeviceSerial,
  }) async {
    if (!dataChannelService.isReady) {
      onTransferError?.call('', 'Data channel not ready');
      return null;
    }

    try {
      final transferId = const Uuid().v4();
      final fileSize = await file.length();
      final totalChunks = (fileSize / chunkSize).ceil();

      // Create progress tracker
      final progress = FileTransferProgress(
        transferId: transferId,
        fileName: file.path.split('/').last,
        totalBytes: fileSize,
        totalChunks: totalChunks,
      );
      _activeTransfers[transferId] = progress;

      // Send file metadata
      final mimeType = _getMimeType(file.path);
      await dataChannelService.sendFileMetadata(
        fileName: file.path.split('/').last,
        fileSize: fileSize,
        mimeType: mimeType,
        transferId: transferId,
      );

      // Send file in chunks
      var bytesRead = 0;
      var chunkIndex = 0;

      final stream = file.openRead();
      final chunks = <Uint8List>[];

      await for (final chunk in stream) {
        chunks.add(chunk);
      }

      for (final chunk in chunks) {
        bytesRead += chunk.length;
        final success = await dataChannelService.sendFileChunk(
          transferId: transferId,
          chunkData: chunk,
          chunkIndex: chunkIndex,
          totalChunks: totalChunks,
        );

        if (success) {
          progress.updateTransferred(chunk.length);
          onProgressUpdate?.call(progress);
          chunkIndex++;
        } else {
          onTransferError?.call(transferId, 'Failed to send chunk');
          _activeTransfers.remove(transferId);
          return null;
        }
      }

      // Calculate checksum
      final bytes = await file.readAsBytes();
      final checksum = sha256.convert(bytes).toString();

      // Signal completion
      await dataChannelService.completeFileTransfer(
        transferId: transferId,
        checksum: checksum,
      );

      _activeTransfers.remove(transferId);
      onTransferComplete?.call(transferId, file.path.split('/').last);
      return transferId;
    } catch (e) {
      onTransferError?.call('', 'Error sending file: $e');
      return null;
    }
  }

  /// Handle incoming file transfer
  Future<void> receiveFile({
    required String transferId,
    required String fileName,
    required int fileSize,
    required String savePath,
  }) async {
    try {
      if (fileSize <= 0 || fileSize > maxInboundFileSizeBytes) {
        onTransferError?.call(transferId, 'Invalid or too large file size');
        return;
      }
      final totalChunks = (fileSize / chunkSize).ceil();
      if (totalChunks > maxChunksPerTransfer) {
        onTransferError?.call(transferId, 'File has too many chunks');
        return;
      }
      final progress = FileTransferProgress(
        transferId: transferId,
        fileName: fileName,
        totalBytes: fileSize,
        totalChunks: totalChunks,
      );
      
      _activeTransfers[transferId] = progress;
      _receivedChunks[transferId] = {};

      onProgressUpdate?.call(progress);
    } catch (e) {
      onTransferError?.call(transferId, 'Error receiving file: $e');
    }
  }

  /// Process incoming file chunk
  Future<void> processFileChunk({
    required String transferId,
    required int chunkIndex,
    required Uint8List chunkData,
  }) async {
    try {
      if (!_activeTransfers.containsKey(transferId)) {
        onTransferError?.call(transferId, 'Unknown transfer ID');
        return;
      }

      final progress = _activeTransfers[transferId]!;
      if (chunkIndex < 0 || chunkIndex >= progress.totalChunks) {
        onTransferError?.call(transferId, 'Invalid chunk index');
        return;
      }
      _receivedChunks[transferId]![chunkIndex] = chunkData;

      progress.updateTransferred(chunkData.length);
      progress.updateChunksReceived(1);
      onProgressUpdate?.call(progress);

      // Acknowledge chunk
      await dataChannelService.acknowledgeChunk(
        transferId: transferId,
        chunkIndex: chunkIndex,
      );
    } catch (e) {
      onTransferError?.call(transferId, 'Error processing chunk: $e');
    }
  }

  /// Complete file transfer
  Future<void> completeFileTransfer({
    required String transferId,
    required String savePath,
    required String expectedChecksum,
  }) async {
    try {
      final chunks = _receivedChunks[transferId];
      if (chunks == null) {
        onTransferError?.call(transferId, 'No chunks received');
        return;
      }

      // Reassemble file
      final sanitizedPath = _sanitizeAndValidateSavePath(savePath);
      final file = File(sanitizedPath);
      final sink = file.openWrite();
      
      for (int i = 0; i < chunks.length; i++) {
        if (chunks.containsKey(i)) {
          sink.add(chunks[i]!);
        }
      }
      
      await sink.close();

      // Verify checksum
      final bytes = await file.readAsBytes();
      final checksum = sha256.convert(bytes).toString();

      if (checksum != expectedChecksum) {
        onTransferError?.call(transferId, 'Checksum mismatch');
        await file.delete();
        return;
      }

      _activeTransfers.remove(transferId);
      _receivedChunks.remove(transferId);
      onTransferComplete?.call(transferId, file.path.split('/').last);
    } catch (e) {
      onTransferError?.call(transferId, 'Error completing transfer: $e');
    }
  }

  String _sanitizeAndValidateSavePath(String savePath) {
    if (savePath.contains('\u0000')) {
      throw ArgumentError('Invalid save path');
    }

    final normalized = p.normalize(savePath);
    final pathSegments = p.split(normalized);
    if (pathSegments.contains('..')) {
      throw ArgumentError('Path traversal detected');
    }

    if (allowedSaveDirectory != null) {
      final baseDir = p.normalize(p.absolute(allowedSaveDirectory!));
      final outputPath = p.normalize(p.absolute(normalized));
      if (!p.isWithin(baseDir, outputPath) && outputPath != baseDir) {
        throw ArgumentError('Save path outside allowed directory');
      }
      return outputPath;
    }

    return normalized;
  }

  /// Get transfer progress
  FileTransferProgress? getTransferProgress(String transferId) {
    return _activeTransfers[transferId];
  }

  /// Cancel transfer
  Future<void> cancelTransfer(String transferId) async {
    _activeTransfers.remove(transferId);
    _receivedChunks.remove(transferId);
  }

  /// Get MIME type from file extension
  String _getMimeType(String filePath) {
    final ext = filePath.split('.').last.toLowerCase();
    const mimeTypes = {
      'pdf': 'application/pdf',
      'doc': 'application/msword',
      'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls': 'application/vnd.ms-excel',
      'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'ppt': 'application/vnd.ms-powerpoint',
      'pptx':
          'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      'txt': 'text/plain',
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'gif': 'image/gif',
      'mp3': 'audio/mpeg',
      'mp4': 'video/mp4',
      'zip': 'application/zip',
    };
    return mimeTypes[ext] ?? 'application/octet-stream';
  }

  /// Dispose resources
  Future<void> dispose() async {
    _activeTransfers.clear();
    _receivedChunks.clear();
  }
}
