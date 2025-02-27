import 'package:dim_client/dim_client.dart';
import 'package:lnc/lnc.dart';

import '../models/amanuensis.dart';
import 'cpu/creator.dart';

class SharedProcessor extends ClientMessageProcessor {
  SharedProcessor(super.facebook, super.messenger);

  @override
  ContentProcessorCreator createCreator() {
    return SharedContentProcessorCreator(facebook!, messenger!);
  }

  @override
  Future<List<SecureMessage>> processSecureMessage(SecureMessage sMsg, ReliableMessage rMsg) async {
    try {
      return await super.processSecureMessage(sMsg, rMsg);
    } catch (e, st) {
      // RangeError: Value not in range: 3
      Log.error('failed to process message: ${rMsg.sender} -> ${rMsg.receiver}: $e, $st');
      // assert(false, 'failed to process message: ${rMsg.sender} -> ${rMsg.receiver}: $e');
      return [];
    }
  }

  @override
  Future<List<InstantMessage>> processInstantMessage(InstantMessage iMsg, ReliableMessage rMsg) async {
    List<InstantMessage> responses = await super.processInstantMessage(iMsg, rMsg);
    // save instant message
    Amanuensis clerk = Amanuensis();
    if (await clerk.saveInstantMessage(iMsg)) {} else {
      // error
      Log.error('failed to save instant message: ${iMsg.sender} -> ${iMsg.receiver}');
      return [];
    }
    return responses;
  }

}
