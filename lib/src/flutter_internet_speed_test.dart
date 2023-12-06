import 'package:flutter_internet_speed_test/src/speed_test_utils.dart';
import 'package:flutter_internet_speed_test/src/test_result.dart';

import 'callbacks_enum.dart';
import 'flutter_internet_speed_test_platform_interface.dart';
import 'models/server_selection_response.dart';

typedef DefaultCallback = void Function();
typedef ResultCallback = void Function(TestResult download, TestResult upload);
typedef TestProgressCallback = void Function(double percent, TestResult data);
typedef ResultCompletionCallback = void Function(TestResult data);
typedef DefaultServerSelectionCallback = void Function(Client? client);

class FlutterInternetSpeedTest {
  static const _defaultDownloadTestServer =
      'http://speedtest.ftp.otenet.gr/files/test10Mb.db';
  static const _defaultUploadTestServer = 'http://speedtest.ftp.otenet.gr/';
  static const _defaultFileSize = 10 * 1024 * 1024; //10 MB

  static final FlutterInternetSpeedTest _instance =
      FlutterInternetSpeedTest._private();

  bool _isTestInProgress = false;
  bool _isCancelled = false;

  factory FlutterInternetSpeedTest() => _instance;

  FlutterInternetSpeedTest._private();

  bool isTestInProgress() => _isTestInProgress;
  TestResult downloadResult =
      TestResult(TestType.download, 0.0, SpeedUnit.kbps);

  Future<void> startTesting({
    required ResultCallback onCompleted,
    DefaultCallback? onStarted,
    ResultCompletionCallback? onDownloadComplete,
    ResultCompletionCallback? onUploadComplete,
    TestProgressCallback? onProgress,
    DefaultCallback? onDefaultServerSelectionInProgress,
    DefaultServerSelectionCallback? onDefaultServerSelectionDone,
    ErrorCallback? onError,
    CancelCallback? onCancel,
    String? downloadTestServer,
    String? uploadTestServer,
    int fileSizeInBytes = _defaultFileSize,
    bool useFastApi = true,
    bool enableDefaultDownloadTestServer = false,
    bool enableDefaultUploadTestServer = false,
  }) async {
    if (_isTestInProgress) {
      return;
    }
    if (await isInternetAvailable() == false) {
      if (onError != null) {
        onError('No internet connection', 'No internet connection');
      }
      return;
    }

    if (fileSizeInBytes < _defaultFileSize) {
      fileSizeInBytes = _defaultFileSize;
    }
    _isTestInProgress = true;

    if (onStarted != null) onStarted();

    // if useFastApi，native server
    if ((downloadTestServer == null || uploadTestServer == null) &&
        useFastApi) {
      if (onDefaultServerSelectionInProgress != null) {
        onDefaultServerSelectionInProgress();
      }
      final serverSelectionResponse =
          await FlutterInternetSpeedTestPlatform.instance.getDefaultServer();

      if (onDefaultServerSelectionDone != null) {
        onDefaultServerSelectionDone(serverSelectionResponse?.client);
      }
      String? url = serverSelectionResponse?.targets?.first.url;
      if (url != null) {
        downloadTestServer = downloadTestServer ?? url;
        uploadTestServer = uploadTestServer ?? url;
      }
    }
    // 如果有帶入參數，匹配為'null'字串，使用預設server
    if (enableDefaultDownloadTestServer) {
      downloadTestServer = _defaultDownloadTestServer;
    }
    if (enableDefaultUploadTestServer) {
      uploadTestServer = _defaultUploadTestServer;
    }
    // if server is null, pass process
    if (downloadTestServer != null) {
      startDownload(
          onCompleted: onCompleted,
          onProgress: onProgress,
          onDownloadComplete: ((data) {
            onDownloadComplete?.call(data);
            if (uploadTestServer != null) {
              startUpload(
                onCompleted: onCompleted,
                onProgress: onProgress,
                onUploadComplete: onUploadComplete,
                onError: onError,
                onCancel: onCancel,
                uploadTestServer: uploadTestServer,
                fileSizeInBytes: fileSizeInBytes,
              );
            }
          }),
          onError: onError,
          onCancel: onCancel,
          downloadTestServer: downloadTestServer,
          fileSizeInBytes: fileSizeInBytes);
    } else if (uploadTestServer != null) {
      startUpload(
        onCompleted: onCompleted,
        onProgress: onProgress,
        onUploadComplete: onUploadComplete,
        onError: onError,
        onCancel: onCancel,
        uploadTestServer: uploadTestServer,
        fileSizeInBytes: fileSizeInBytes,
      );
    }

    if (_isCancelled) {
      if (onCancel != null) {
        onCancel();
        _isTestInProgress = false;
        _isCancelled = false;
        return;
      }
    }
  }

  void enableLog() {
    FlutterInternetSpeedTestPlatform.instance.toggleLog(value: true);
  }

  void disableLog() {
    FlutterInternetSpeedTestPlatform.instance.toggleLog(value: false);
  }

  Future<bool> cancelTest() async {
    _isCancelled = true;
    return await FlutterInternetSpeedTestPlatform.instance.cancelTest();
  }

  bool get isLogEnabled => FlutterInternetSpeedTestPlatform.instance.logEnabled;

  void startDownload({
    required ResultCallback onCompleted,
    TestProgressCallback? onProgress,
    ResultCompletionCallback? onDownloadComplete,
    ErrorCallback? onError,
    CancelCallback? onCancel,
    required String downloadTestServer,
    int fileSizeInBytes = _defaultFileSize,
  }) {
    final startDownloadTimeStamp = DateTime.now().millisecondsSinceEpoch;
    FlutterInternetSpeedTestPlatform.instance.startDownloadTesting(
      onDone: (double transferRate, SpeedUnit unit) {
        final downloadDuration =
            DateTime.now().millisecondsSinceEpoch - startDownloadTimeStamp;
        downloadResult = TestResult(TestType.download, transferRate, unit,
            durationInMillis: downloadDuration);

        if (onProgress != null) onProgress(100, downloadResult);
        if (onDownloadComplete != null) onDownloadComplete(downloadResult);
      },
      onProgress: (double percent, double transferRate, SpeedUnit unit) {
        final downloadProgressResult =
            TestResult(TestType.download, transferRate, unit);
        if (onProgress != null) onProgress(percent, downloadProgressResult);
      },
      onError: (String errorMessage, String speedTestError) {
        if (onError != null) onError(errorMessage, speedTestError);
        _isTestInProgress = false;
        _isCancelled = false;
      },
      onCancel: () {
        if (onCancel != null) onCancel();
        _isTestInProgress = false;
        _isCancelled = false;
      },
      fileSize: fileSizeInBytes,
      testServer: downloadTestServer,
    );
  }

  void startUpload({
    required ResultCallback onCompleted,
    TestProgressCallback? onProgress,
    ResultCompletionCallback? onUploadComplete,
    ErrorCallback? onError,
    CancelCallback? onCancel,
    String? uploadTestServer,
    int fileSizeInBytes = _defaultFileSize,
  }) {
    final startUploadTimeStamp = DateTime.now().millisecondsSinceEpoch;
    FlutterInternetSpeedTestPlatform.instance.startUploadTesting(
      onDone: (double transferRate, SpeedUnit unit) {
        final uploadDuration =
            DateTime.now().millisecondsSinceEpoch - startUploadTimeStamp;
        final uploadResult = TestResult(TestType.upload, transferRate, unit,
            durationInMillis: uploadDuration);

        if (onProgress != null) onProgress(100, uploadResult);
        if (onUploadComplete != null) onUploadComplete(uploadResult);

        onCompleted(downloadResult, uploadResult);
        _isTestInProgress = false;
        _isCancelled = false;
      },
      onProgress: (double percent, double transferRate, SpeedUnit unit) {
        final uploadProgressResult =
            TestResult(TestType.upload, transferRate, unit);
        if (onProgress != null) {
          onProgress(percent, uploadProgressResult);
        }
      },
      onError: (String errorMessage, String speedTestError) {
        if (onError != null) onError(errorMessage, speedTestError);
        _isTestInProgress = false;
        _isCancelled = false;
      },
      onCancel: () {
        if (onCancel != null) onCancel();
        _isTestInProgress = false;
        _isCancelled = false;
      },
      fileSize: fileSizeInBytes,
      testServer: uploadTestServer!,
    );
  }
}
