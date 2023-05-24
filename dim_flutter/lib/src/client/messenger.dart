import 'dart:typed_data';

import 'package:dim_client/dim_client.dart';

import '../models/conversation.dart';
import 'compatible.dart';
import 'shared.dart';

class SharedMessenger extends ClientMessenger {
  SharedMessenger(super.session, super.facebook, super.mdb);

  @override
  void suspendInstantMessage(InstantMessage iMsg, Map info) {
    Amanuensis clerk = Amanuensis();
    clerk.suspendInstantMessage(iMsg);
  }

  @override
  void suspendReliableMessage(ReliableMessage rMsg, Map info) {
    Amanuensis clerk = Amanuensis();
    clerk.suspendReliableMessage(rMsg);
  }

  @override
  Future<Uint8List> serializeContent(Content content,
      SymmetricKey password, InstantMessage iMsg) async {
    if (content is Command) {
      content = Compatible.fixCommand(content);
    }
    return await super.serializeContent(content, password, iMsg);
  }

  @override
  Future<Content?> deserializeContent(Uint8List data, SymmetricKey password,
      SecureMessage sMsg) async {
    Content? content = await super.deserializeContent(data, password, sMsg);
    if (content is Command) {
      content = Compatible.fixCommand(content);
    }
    return content;
  }

  @override
  Future<ReliableMessage?> sendInstantMessage(InstantMessage iMsg, {int priority = 0}) async {
    ReliableMessage? rMsg = await super.sendInstantMessage(iMsg, priority: priority);
    if (rMsg != null) {
      // keep signature for checking traces
      iMsg['signature'] = rMsg.getString('signature');
    }
    return rMsg;
  }

  @override
  Future<void> handshakeSuccess() async {
    await super.handshakeSuccess();
    // // 1. broadcast current documents after handshake success
    // await broadcastDocument();
    // 2. broadcast login command with current station info
    GlobalVariable shared = GlobalVariable();
    User? user = await shared.facebook.currentUser;
    if (user == null) {
      assert(false, 'should not happen');
    } else {
      await broadcastLogin(user.identifier, shared.terminal.userAgent);
    }
  }

}
