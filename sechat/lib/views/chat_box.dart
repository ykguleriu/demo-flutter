import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_section_list/flutter_section_list.dart';

import 'package:dim_client/dim_client.dart';
import 'package:dim_client/dim_client.dart' as lnc;

import '../client/constants.dart';
import '../client/shared.dart';
import '../models/contact.dart';
import '../models/conversation.dart';
import '../widgets/alert.dart';
import '../widgets/facade.dart';
import '../widgets/picker.dart';
import 'profile.dart';
import 'styles.dart';

///
///  Chat Box
///
class ChatBox extends StatefulWidget {
  const ChatBox(this.info, {super.key});

  final ContactInfo info;

  static void open(BuildContext context, ContactInfo info) {
    showCupertinoDialog(
      context: context,
      builder: (context) => ChatBox(info),
    ).then((value) {
      if (info is Conversation) {
        info.unread = 0;
      }
      var nc = NotificationCenter();
      nc.postNotification(NotificationNames.kConversationUpdated, null, {
        'action': 'read',
        'ID': info.identifier,
      });
    });
  }

  @override
  State<ChatBox> createState() => _ChatBoxState();
}

class _ChatBoxState extends State<ChatBox> implements lnc.Observer {
  _ChatBoxState() {
    _dataSource = _HistoryDataSource();

    var nc = lnc.NotificationCenter();
    nc.addObserver(this, NotificationNames.kMessageUpdated);
  }

  @override
  void dispose() {
    super.dispose();
    var nc = lnc.NotificationCenter();
    nc.removeObserver(this, NotificationNames.kMessageUpdated);
  }

  @override
  Future<void> onReceiveNotification(lnc.Notification notification) async {
    Map? userInfo = notification.userInfo;
    ID? cid = userInfo?['ID'];
    if (cid == widget.info.identifier) {
      _reload();
    }
  }

  late final _HistoryDataSource _dataSource;

  User? _currentUser;

  Future<void> _reload() async {
    GlobalVariable shared = GlobalVariable();
    _currentUser = await shared.facebook.currentUser;
    var pair = await shared.database.getInstantMessages(widget.info.identifier);
    Log.warning('message updated: ${pair.first.length}');
    setState(() {
      _dataSource.refresh(pair.first);
    });
  }

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Styles.backgroundColor,
      appBar: CupertinoNavigationBar(
        backgroundColor: Styles.navigationBarBackground,
        border: Styles.navigationBarBorder,
        middle: Text(widget.info.name),
        trailing: IconButton(
          iconSize: Styles.navigationBarIconSize,
          color: Styles.navigationBarIconColor,
          icon: const Icon(Icons.more_horiz),
          onPressed: () => _openDetail(context, widget.info),
        ),
      ),
      body: _body(context),
    );
  }

  Widget _body(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.end,
    children: [
      Expanded(
        flex: 1,
        child: SectionListView.builder(
          reverse: true,
          adapter: _HistoryAdapter(_currentUser, widget.info,
              dataSource: _dataSource,
          ),
        ),
      ),
      Container(
        color: CupertinoColors.systemBackground,
        child: _InputTray(widget.info),
      ),
    ],
  );

}

class _HistoryAdapter with SectionAdapterMixin {
  _HistoryAdapter(User? currentUser, ContactInfo conversation, {required _HistoryDataSource dataSource})
      : _currentUser = currentUser, _conversation = conversation, _dataSource = dataSource;

  final User? _currentUser;
  final ContactInfo _conversation;
  final _HistoryDataSource _dataSource;

  @override
  int numberOfItems(int section) {
    return _dataSource.getItemCount();
  }

  @override
  Widget getItem(BuildContext context, IndexPath indexPath) {
    InstantMessage iMsg = _dataSource.getItem(indexPath.item);
    ID sender = iMsg.sender;
    DateTime? time = iMsg.time;
    Content content = iMsg.content;
    if (content is Command) {
      return _showCommand(content, sender, context: context);
    }
    bool isMe = sender == _currentUser?.identifier;
    bool isGroupChat = _conversation.identifier.isGroup;
    const radius = Radius.circular(12);
    const borderRadius = BorderRadius.all(radius);
    return Container(
      margin: const EdgeInsets.only(left: 8, top: 4, right: 8, bottom: 4),
      // color: Colors.yellowAccent,
      child: Column(
        children: [
          if (time != null)
            Text(Time.getTimeString(time),
              style: const TextStyle(color: Colors.grey, fontSize: 10),
            ),
          Row(
            mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isMe)
                IconButton(
                  icon: Facade.fromID(sender),
                  onPressed: () => _openProfile(context, sender, _conversation),
                ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isMe && (isGroupChat || sender != _conversation.identifier))
                    Container(
                      margin: const EdgeInsets.only(left: 8),
                      child: Text(sender.string,
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ),
                  Container(
                    margin: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    constraints: const BoxConstraints(maxWidth: 240),
                    decoration: BoxDecoration(
                      color: isMe ? Colors.lightGreen : Colors.white,
                      borderRadius: isMe
                          ? borderRadius.subtract(
                          const BorderRadius.only(topRight: radius))
                          : borderRadius.subtract(
                          const BorderRadius.only(topLeft: radius)),
                    ),
                    child: _showContent(content, sender, context: context),
                  ),
                ],
              ),
              if (isMe)
                IconButton(
                  icon: Facade.fromID(sender),
                  onPressed: () {
                    // do nothing
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _showCommand(Command content, ID sender, {required BuildContext context}) {
    return Text(content.cmd);
  }

  Widget _showContent(Content content, ID sender, {required BuildContext context}) {
    if (content is ImageContent) {
      return _showImageContent(content, sender, context: context);
    } else if (content is AudioContent) {
      return _showAudioContent(content, sender, context: context);
    } else if (content is VideoContent) {
      return _showVideoContent(content, sender, context: context);
    }
    return Text('${content["text"]}');
  }

  Widget _showImageContent(ImageContent content, ID sender, {required BuildContext context}) {
    String? filename = content.filename;
    String? url = content.url;
    return Text('Image[$filename]: $url');
  }

  Widget _showAudioContent(AudioContent content, ID sender, {required BuildContext context}) {
    String? filename = content.filename;
    String? url = content.url;
    return Text('Voice[$filename]: $url');
  }

  Widget _showVideoContent(VideoContent content, ID sender, {required BuildContext context}) {
    String? filename = content.filename;
    String? url = content.url;
    return Text('Movie[$filename]: $url');
  }
}

class _HistoryDataSource {

  List<InstantMessage> _messages = [];

  void refresh(List<InstantMessage> history) {
    Log.debug('refreshing ${history.length} message(s)');
    _messages = history;
  }

  int getItemCount() => _messages.length;

  InstantMessage getItem(int index) => _messages[index];
}

//--------

class _InputTray extends StatefulWidget {
  const _InputTray(this.info);

  final ContactInfo info;

  @override
  State<StatefulWidget> createState() => _InputState();

}

class _InputState extends State<_InputTray> {

  final TextEditingController _controller = TextEditingController();

  bool _isVoice = false;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (!_isVoice)
      CupertinoButton(
        child: const Icon(CupertinoIcons.mic_circle),
        onPressed: () => setState(() {
          _isVoice = true;
        }),
      ),
      if (_isVoice)
      CupertinoButton(
        child: const Icon(CupertinoIcons.keyboard),
        onPressed: () => setState(() {
          _isVoice = false;
        }),
      ),
      if (!_isVoice)
      Expanded(
        flex: 1,
        child: CupertinoTextField(
          minLines: 1,
          maxLines: 8,
          controller: _controller,
          placeholder: 'Input text message',
          textInputAction: TextInputAction.send,
          onSubmitted: (value) => _sendText(context, _controller, widget.info),
          onChanged: (value) => setState(() {}),
        ),
      ),
      if (_isVoice)
      Expanded(
        flex: 1,
        child: TextButton(
          child: const Text('Press and record'),
          onPressed: () {
          },
        ),
      ),
      if (_controller.text.isEmpty)
      CupertinoButton(
        child: const Icon(Icons.add_circle_outline),
        onPressed: () => _sendImage(context, widget.info),
      ),
      if (_controller.text.isNotEmpty)
      CupertinoButton(
        child: const Icon(Icons.send),
        onPressed: () => _sendText(context, _controller, widget.info),
      ),
    ],
  );

}

//--------

void _sendText(BuildContext context, TextEditingController controller, ContactInfo chat) {
  String text = controller.text;
  if (text.isNotEmpty) {
    GlobalVariable shared = GlobalVariable();
    shared.emitter.sendText(text, chat.identifier);
  }
  controller.text = '';
}

void _sendImage(BuildContext context, ContactInfo chat) {
  openImagePicker(context, onRead: (path, data) async {
    Uint8List thumbnail = await FlutterImageCompress.compressWithList(data,
        minHeight: 128,
        minWidth: 128,
        quality: 20,
    );
    GlobalVariable shared = GlobalVariable();
    shared.emitter.sendImage(data, thumbnail, chat.identifier);
  });
}

void _openDetail(BuildContext context, ContactInfo info) {
  ID identifier = info.identifier;
  if (identifier.isUser) {
    _openProfile(context, identifier, info);
  } else {
    Alert.show(context, 'Coming soon', 'show group detail: $info');
  }
}

void _openProfile(BuildContext context, ID uid, ContactInfo info) {
  ProfilePage.open(context, uid, fromWhere: info.identifier);
}
