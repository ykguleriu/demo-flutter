import 'dart:typed_data';

import 'package:dim_client/dim_client.dart';
import 'package:lnc/lnc.dart';

import '../channels/manager.dart';
import '../channels/transfer.dart';
import '../models/amanuensis.dart';
import '../network/ftp.dart';

import 'constants.dart';
import 'group.dart';
import 'shared.dart';

class Emitter implements Observer {
  Emitter() {
    var nc = NotificationCenter();
    nc.addObserver(this, NotificationNames.kFileUploadSuccess);
    nc.addObserver(this, NotificationNames.kFileUploadFailure);
  }
  
  /// filename => task
  final Map<String, InstantMessage> _outgoing = {};

  // void _addTask(String filename, InstantMessage item) {
  //   _outgoing[filename] = item;
  // }

  InstantMessage? _popTask(String filename) {
    InstantMessage? item = _outgoing[filename];
    if (item != null) {
      _outgoing.remove(filename);
    }
    return item;
  }

  void purge() {
    // TODO: remove expired messages in the map
  }

  @override
  Future<void> onReceiveNotification(Notification notification) async {
    String name = notification.name;
    Map info = notification.userInfo!;
    if (name == NotificationNames.kFileUploadSuccess) {
      String filename = info['filename'];
      Uri url = info['url'];
      await _onUploadSuccess(filename, url);
    } else if (name == NotificationNames.kFileUploadFailure) {
      String filename = info['filename'];
      _onUploadFailed(filename);
    }
  }

  Future<void> _onUploadSuccess(String filename, Uri url) async {
    InstantMessage? iMsg = _popTask(filename);
    if (iMsg == null) {
      Log.error('failed to get task: $filename, url: $url');
      return;
    }
    Log.info('get task for file: $filename, url: $url');
    // file data uploaded to FTP server, replace it with download URL
    // and send the content to station
    FileContent content = iMsg.content as FileContent;
    // content.data = null;
    content.url = url;
    return await _sendInstantMessage(iMsg).onError((error, stackTrace) {
      Log.error('failed to send message: $error');
    });
  }

  Future<void> _onUploadFailed(String filename) async {
    InstantMessage? iMsg = _popTask(filename);
    if (iMsg == null) {
      Log.error('failed to get task: $filename');
      return;
    }
    Log.info('get task for file: $filename');
    // file data failed to upload, mark it error
    iMsg['error'] = {
      'message': 'failed to upload file',
    };
    return await _saveInstantMessage(iMsg);
  }

  static Future<void> _sendInstantMessage(InstantMessage iMsg) async {
    Log.info('send instant message (type=${iMsg.content.type}): ${iMsg.sender} -> ${iMsg.receiver}');
    // send by shared messenger
    GlobalVariable shared = GlobalVariable();
    ClientMessenger? mess = shared.messenger;
    await mess?.sendInstantMessage(iMsg);
    // save instant message
    await _saveInstantMessage(iMsg);
  }

  static Future<void> _saveInstantMessage(InstantMessage iMsg) async {
    Amanuensis clerk = Amanuensis();
    await clerk.saveInstantMessage(iMsg).onError((error, stackTrace) {
      Log.error('failed to save message: $error');
      return false;
    });
  }

  ///  Upload file data encrypted with password
  ///
  /// @param content  - file content
  /// @param password - encrypt/decrypt key
  /// @param sender   - from where
  /// @return false on error
  Future<bool> uploadFileData(FileContent content,
      {required SymmetricKey password, required ID sender}) async {
    // 0. check file content
    Uint8List? data = content.data;
    if (data == null) {
      Log.warning('already uploaded: ${content.url}');
      return false;
    }
    assert(content.password == null, 'file content error: $content');
    assert(content.url == null, 'file content error: $content');
    // 1. save origin file data
    String? filename = content.filename;
    assert(filename != null, 'content filename should not empty: $content');
    int len = await FileTransfer.cacheFileData(data, filename!);
    if (len != data.length) {
      Log.error('failed to save file data (len=${data.length}): $filename');
      return false;
    }
    // 2. add upload task with encrypted data
    Uint8List encrypted = password.encrypt(data, content);
    filename = FileTransfer.filenameFromData(encrypted, filename);
    ChannelManager man = ChannelManager();
    FileTransferChannel ftp = man.ftpChannel;
    Uri? url = await ftp.uploadEncryptData(encrypted, filename, sender);
    if (url == null) {
      Log.error('failed to upload: ${content.filename} -> $filename');
      // TODO: mark message failed
      return false;
    } else {
      // upload success
      Log.info('uploaded filename: ${content.filename} -> $filename => $url');
    }
    // 3. replace file data with URL & decrypt key
    content.url = url;
    content.password = password;
    content.data = null;
    return true;
  }

  ///  Send text message to receiver
  ///
  /// @param text     - text message
  /// @param receiver - receiver ID
  /// @throws IOException on failed to save message
  Future<void> sendText(String text, ID receiver) async {
    TextContent content = TextContent.create(text);
    await sendContent(content, receiver);
  }

  ///  Send image message to receiver
  ///
  /// @param jpeg      - image data
  /// @param thumbnail - image thumbnail
  /// @param receiver  - receiver ID
  /// @throws IOException on failed to save message
  Future<void> sendImage(Uint8List jpeg, Uint8List thumbnail, ID receiver) async {
    assert(jpeg.isNotEmpty, 'image data should not empty');
    String filename = Hex.encode(MD5.digest(jpeg));
    filename += ".jpeg";
    TransportableData ted = TransportableData.create(jpeg);
    ImageContent content = FileContent.image(filename: filename, data: ted);
    // add image data length & thumbnail into message content
    content['length'] = jpeg.length;
    content.thumbnail = thumbnail;
    await sendContent(content, receiver);
  }

  ///  Send voice message to receiver
  ///
  /// @param mp4      - voice file
  /// @param duration - length
  /// @param receiver - receiver ID
  /// @throws IOException on failed to save message
  Future<void> sendVoice(Uint8List mp4, double duration, ID receiver) async {
    assert(mp4.isNotEmpty, 'voice data should not empty');
    String filename = Hex.encode(MD5.digest(mp4));
    filename += ".mp4";
    TransportableData ted = TransportableData.create(mp4);
    AudioContent content = FileContent.audio(filename: filename, data: ted);
    // add voice data length & duration into message content
    content['length'] = mp4.length;
    content['duration'] = duration;
    await sendContent(content, receiver);
  }

  Future<Pair<InstantMessage?, ReliableMessage?>> sendContent(Content content, ID receiver) async {
    if (receiver.isGroup) {
      assert(!content.containsKey('group') || content.group == receiver, 'group ID error: $receiver, $content');
      content.group = receiver;
    }
    GlobalVariable shared = GlobalVariable();
    User? user = await shared.facebook.currentUser;
    if (user == null) {
      assert(false, 'failed to get current user');
      return const Pair(null, null);
    }
    ID sender = user.identifier;
    // 1. pack instant message
    Envelope envelope = Envelope.create(sender: sender, receiver: receiver);
    InstantMessage iMsg = InstantMessage.create(envelope, content);
    // 2. check file content
    if (content is FileContent) {
      // encrypt & upload file data before send out
      if (content.data != null/* && content.url == null*/) {
        SymmetricKey? password = await shared.messenger?.getEncryptKey(iMsg);
        if (password == null) {
          assert(false, 'failed to get encrypt key: ''$sender => $receiver, ${iMsg['group']}');
          return Pair(iMsg, null);
        } else if (await uploadFileData(content, password: password, sender: sender)) {
          Log.info('uploaded file data for sender: $sender, ${content.filename}');
        } else {
          Log.error('failed to upload file data for sender: $sender, ${content.filename}');
          return Pair(iMsg, null);
        }
      }
    }
    // 3. send
    ReliableMessage? rMsg;
    if (receiver.isGroup) {
      // group message
      SharedGroupManager manager = SharedGroupManager();
      rMsg = await manager.sendInstantMessage(iMsg);
    } else {
      rMsg = await shared.messenger?.sendInstantMessage(iMsg);
    }
    // save instant message
    await _saveInstantMessage(iMsg);
    // check respond
    if (rMsg == null && !iMsg.receiver.isGroup) {
      Log.warning('not send yet (type=${content.type}): $receiver');
    }
    return Pair(iMsg, rMsg);
  }

}
