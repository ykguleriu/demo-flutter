import 'package:flutter/services.dart';

import 'package:dim_client/dim_client.dart';
import 'package:lnc/lnc.dart';

import '../common/constants.dart';
import '../filesys/paths.dart';
import '../models/config.dart';
import '../widgets/browse_html.dart';
import 'manager.dart';

class FileTransferChannel extends SafeChannel {
  FileTransferChannel(super.name) {
    setMethodCallHandler(_handle);
  }

  final Map<String, Uri> _uploads = {};    // filename => download url
  final Map<Uri, String> _downloads = {};  // url => file path

  static final Uri _upWaiting = Uri.parse('https://chat.dim.sechat/up/waiting');
  static final Uri _upError = Uri.parse('https://chat.dim.sechat/up/error');
  static const String _downWaiting = '/tmp/down/waiting';
  static const String _downError = '/tmp/down/error';

  /// upload task will be expired after 10 minutes
  static double uploadExpires = 600.0;

  /// root directory for local storage
  String? _cachesDirectory;
  String? _temporaryDirectory;
  bool _apiUpdated = false;

  Future<String?> get cachesDirectory async {
    String? dir = _cachesDirectory;
    if (dir == null) {
      dir = await invoke(ChannelMethods.getCachesDirectory, null);
      _cachesDirectory = dir;
    }
    return dir;
  }
  Future<String?> get temporaryDirectory async {
    String? dir = _temporaryDirectory;
    if (dir == null) {
      dir = await invoke(ChannelMethods.getTemporaryDirectory, null);
      _temporaryDirectory = dir;
    }
    return dir;
  }

  Future<void> _prepare() async {
    if (_apiUpdated) {
      return;
    }
    // config for upload
    Config config = Config();
    List api = await config.uploadAPI;
    String url;
    String enigma;
    // TODO: pick up the fastest API for upload
    var chosen = api[0];
    if (chosen is Map) {
      url = chosen['url'];
      enigma = chosen['enigma'];
    } else {
      assert(chosen is String, 'API error: $api');
      url = chosen;
      enigma = '';
    }
    if (url.isEmpty) {
      assert(false, 'config error: $api');
      return;
    }
    String? secret = await Enigma().getSecret(enigma);
    if (secret == null || secret.isEmpty) {
      assert(false, 'failed to get MD5 secret: $enigma');
      return;
    }
    Log.warning('setUploadConfig: $secret (enigma: $enigma), $url');
    await setUploadConfig(api: url, secret: secret);
    _apiUpdated = true;
  }

  /// MethCallHandler
  Future<void> _handle(MethodCall call) async {
    String method = call.method;
    var arguments = call.arguments;
    if (method == ChannelMethods.onDownloadSuccess) {
      // onDownloadSuccess
      String urlString = arguments['url'];
      Uri? url = HtmlUri.parseUri(urlString);
      String path = arguments['path'];
      Log.warning('download success: $url -> $path');
      if (url == null) {} else {
        _downloads[url] = path;
      }
    } else if (method == ChannelMethods.onDownloadFailure) {
      // onDownloadFailed
      String urlString = arguments['url'];
      Uri? url = HtmlUri.parseUri(urlString);
      Log.error('download $url error: ${arguments['error']}');
      if (url == null) {} else {
        _downloads[url] = _downError;
      }
    } else if (method == ChannelMethods.onUploadSuccess) {
      // onUploadSuccess
      String? filename = arguments['filename'];
      filename ??= Paths.filename(arguments['path']);
      Map res = arguments['response'];
      Uri? url = HtmlUri.parseUri(res['url']);
      Log.warning('upload success: $filename -> $url');
      if (url == null) {} else {
        _uploads[filename!] = url;
      }
    } else if (method == ChannelMethods.onUploadFailure) {
      // onUploadFailed
      String? filename = arguments['filename'];
      filename ??= Paths.filename(arguments['path']);
      Log.error('upload $filename error: ${arguments['error']}');
      _uploads[filename!] = _upError;
    }
  }

  //
  //  Invoke Methods
  //

  /// set upload API & secret key
  Future<void> setUploadConfig({required String api, required String secret}) async =>
      await invoke(ChannelMethods.setUploadAPI, {
        'api': api,
        'secret': secret,
      });

  ///  Upload avatar image data for user
  ///
  /// @param data     - image data
  /// @param filename - image filename ('${hex(md5(data))}.jpg')
  /// @param sender   - user ID
  /// @return remote URL if same file uploaded before
  Future<Uri?> uploadAvatar(Uint8List data, String filename, ID sender) async =>
      await _doUpload(ChannelMethods.uploadAvatar, data, filename, sender);

  ///  Upload encrypted file data for user
  ///
  /// @param data     - encrypted data
  /// @param filename - data file name ('${hex(md5(data))}.mp4')
  /// @param sender   - user ID
  /// @return remote URL if same file uploaded before
  Future<Uri?> uploadEncryptData(Uint8List data, String filename, ID sender) async =>
      await _doUpload(ChannelMethods.uploadFile, data, filename, sender);

  ///  Download avatar image file
  ///
  /// @param url      - avatar URL
  /// @return local path if same file downloaded before
  Future<String?> downloadAvatar(Uri url) async =>
      await _doDownload(ChannelMethods.downloadAvatar, url);

  ///  Download encrypted file data for user
  ///
  /// @param url      - relay URL
  /// @return temporary path if same file downloaded before
  Future<String?> downloadFile(Uri url) async =>
      await _doDownload(ChannelMethods.downloadFile, url);

  Future<Uri?> _doUpload(String method, Uint8List data, String filename, ID sender) async {
    await _prepare();
    // 1. check old task
    Uri? url = _uploads[filename];
    if (url == _upError) {
      Log.warning('error task, try to upload again: $filename');
      url = null;
    }
    if (url == null) {
      Log.info('try to upload: $filename');
      _uploads[filename] = _upWaiting;
      // call ftp client to upload
      url = await invoke(method, {
        'data': data,
        'filename': filename,
        'sender': sender.toString(),
      });
      Log.info('uploaded: $filename -> $url');
      url ??= _upWaiting;
      _uploads[filename] = url;
    }
    // 2. do upload
    if (url == _upWaiting) {
      double now = Time.currentTimeSeconds;
      double expired = now + uploadExpires;
      while (url == _upWaiting) {
        // wait a while to check the result
        await Future.delayed(const Duration(milliseconds: 512));
        url = _uploads[filename];
        now = Time.currentTimeSeconds;
        if (now > expired) {
          Log.error('upload expired: $filename');
          break;
        }
      }
      // check result
      if (url == null || url == _upWaiting) {
        url = _upError;
        _uploads[filename] = url;
      }
    }
    Log.info('upload result: $filename -> $url');
    // 3. return url when not error
    String notification;
    if (url == _upError) {
      url = null;
      notification = NotificationNames.kFileUploadFailure;
    } else {
      assert(url != _upWaiting, 'upload result error: $filename -> $url');
      notification = NotificationNames.kFileUploadSuccess;
    }
    // post notification async
    var nc = NotificationCenter();
    nc.postNotification(notification, this, {
      'filename': filename,
      'url': url,
    });
    return url;
  }

  Future<String?> _doDownload(String method, Uri url) async {
    await _prepare();
    // 1. check old task
    String? path = _downloads[url];
    if (path == _downError) {
      Log.warning('error task, try to download again: $url');
      path = null;
    }
    if (path == null) {
      Log.info('try to download: $url');
      _downloads[url] = _downWaiting;
      // call ftp client to download
      path = await invoke(method, {
        'url': url.toString(),
      });
      Log.info('downloaded: $url -> $path');
      path ??= _downWaiting;
      _downloads[url] = path;
    }
    // 2. check download tasks
    if (path == _downWaiting) {
      double now = Time.currentTimeSeconds;
      double expired = now + uploadExpires;
      while (path == _downWaiting) {
        // wait a while to check the result
        await Future.delayed(const Duration(milliseconds: 512));
        path = _downloads[url];
        now = Time.currentTimeSeconds;
        if (now > expired) {
          Log.error('download expired: $url');
          break;
        }
      }
      // check result
      if (path == null || path == _downWaiting) {
        path = _downError;
        _downloads[url] = path;
      }
    } else {
      Log.debug('memory cached file: $path -> $url');
    }
    // 3. return url when not error
    if (path == _downError) {
      path = null;
    } else {
      assert(path != _downWaiting, 'download task error: $url -> $path');
    }
    return path;
  }

}
