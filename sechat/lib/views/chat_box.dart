import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_section_list/flutter_section_list.dart';

import 'package:dim_client/dim_client.dart';
import 'package:dim_client/dim_client.dart' as lnc;

import '../client/constants.dart';
import '../client/shared.dart';
import '../models/contact.dart';
import '../models/conversation.dart';
import '../widgets/alert.dart';
import '../widgets/facade.dart';
import '../widgets/message.dart';
import '../widgets/title.dart';
import 'chat_flag.dart';
import 'chat_tray.dart';
import 'profile.dart';
import 'styles.dart';

///
///  Chat Box
///
class ChatBox extends StatefulWidget {
  const ChatBox(this.info, {super.key});

  final ContactInfo info;

  static int maxCountOfMessages = 2048;

  static void open(BuildContext context, ContactInfo info) {
    showCupertinoDialog(
      context: context,
      builder: (context) => ChatBox(info),
    ).then((value) {
      if (info is Conversation) {
        info.unread = 0;
      }
      Amanuensis clerk = Amanuensis();
      clerk.clearUnread(info.identifier);
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
    nc.addObserver(this, NotificationNames.kDocumentUpdated);
  }

  @override
  void dispose() {
    super.dispose();
    var nc = lnc.NotificationCenter();
    nc.removeObserver(this, NotificationNames.kDocumentUpdated);
    nc.removeObserver(this, NotificationNames.kMessageUpdated);
  }

  @override
  Future<void> onReceiveNotification(lnc.Notification notification) async {
    String name = notification.name;
    Map? userInfo = notification.userInfo;
    ID? cid = userInfo?['ID'];
    if (cid == null) {
      Log.error('notification error: $notification');
    }
    if (name == NotificationNames.kMessageUpdated) {
      if (cid == widget.info.identifier) {
        await _reload();
      }
    } else if (name == NotificationNames.kDocumentUpdated) {
      if (cid == widget.info.identifier) {
        await _reload();
      } else {
        // TODO: check members for group chat?
      }
    } else {
      assert(false, 'notification error: $notification');
    }
  }

  late final _HistoryDataSource _dataSource;

  Future<void> _reload() async {
    GlobalVariable shared = GlobalVariable();
    ContentViewUtils.currentUser = await shared.facebook.currentUser;
    var pair = await shared.database.getInstantMessages(widget.info.identifier,
        limit: ChatBox.maxCountOfMessages);
    Log.warning('message updated: ${pair.first.length}');
    if (mounted) {
      setState(() {
        _dataSource.refresh(pair.first);
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Styles.backgroundColor,
    appBar: CupertinoNavigationBar(
      backgroundColor: Styles.navigationBarBackground,
      border: Styles.navigationBarBorder,
      middle: StatedTitleView(() => widget.info.name),
      trailing: IconButton(
        iconSize: Styles.navigationBarIconSize,
        color: Styles.navigationBarIconColor,
        icon: const Icon(Icons.more_horiz),
        onPressed: () => _openDetail(context, widget.info),
      ),
    ),
    body: _body(context),
  );

  Widget _body(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.end,
    children: [
      Expanded(
        flex: 1,
        child: SectionListView.builder(
          reverse: true,
          adapter: _HistoryAdapter(widget.info,
              dataSource: _dataSource,
          ),
        ),
      ),
      Container(
        color: Styles.inputTrayBackground,
        child: ChatInputTray(widget.info),
      ),
    ],
  );

}

class _HistoryAdapter with SectionAdapterMixin {
  _HistoryAdapter(ContactInfo conversation, {required _HistoryDataSource dataSource})
      : _conversation = conversation, _dataSource = dataSource;

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
    Content content = iMsg.content;
    Widget? timeLabel = _getTimeLabel(iMsg, indexPath);
    String? commandText = _getCommandText(content, sender, indexPath);
    Widget? commandLabel;
    Widget? contentView;
    if (commandText == null) {
      Widget? nameLabel = _getNameLabel(sender);
      int mainFlex = 3;
      // show content
      if (content is FileContent) {
        mainFlex = 1;
      }
      bool isMine = sender == ContentViewUtils.currentUser?.identifier;
      const radius = Radius.circular(12);
      const borderRadius = BorderRadius.all(radius);
      // create content view
      contentView = Container(
        margin: Styles.messageContentMargin,
        constraints: content is ImageContent ? const BoxConstraints(maxHeight: 256) : null,
        child: ClipRRect(
          borderRadius: isMine
              ? borderRadius.subtract(
              const BorderRadius.only(topRight: radius))
              : borderRadius.subtract(
              const BorderRadius.only(topLeft: radius)),
          child: _getContentView(context, content, sender),
        ),
      );
      // create content frame
      contentView = _getContentFrame(context, sender, mainFlex, isMine,
        image: Facade.fromID(sender),
        name: nameLabel,
        body: contentView,
        flag: isMine ? ChatSendFlag(iMsg) : null,
      );
    } else if (commandText.isEmpty) {
      // hidden command
      return Container();
    } else {
      // show command
      commandLabel = _getCommandLabel(commandText);
    }
    return Container(
      margin: Styles.messageItemMargin,
      child: Column(
        children: [
          if (timeLabel != null)
            timeLabel,
          if (commandLabel != null)
            commandLabel,
          if (contentView != null)
            contentView,
        ],
      ),
    );
  }

  Widget? _getTimeLabel(InstantMessage iMsg, IndexPath indexPath) {
    DateTime? time = iMsg.time;
    if (time == null) {
      assert(false, 'message time not found: ${iMsg.dictionary}');
      return null;
    }
    int total = _dataSource.getItemCount();
    if (indexPath.item < total - 1) {
      DateTime? prev = _dataSource.getItem(indexPath.item + 1).time;
      if (prev != null) {
        int delta = time.millisecondsSinceEpoch - prev.millisecondsSinceEpoch;
        if (-120000 < delta && delta < 120000) {
          // it is too close to the previous message,
          // hide this time label to reduce noises.
          return null;
        }
      }
    }
    return Text(Time.getTimeString(time), style: Styles.messageTimeTextStyle);
  }

  Widget? _getNameLabel(ID sender) {
    if (sender == ContentViewUtils.currentUser?.identifier) {
      // no need to show my name in chat box
      return null;
    } else if (sender == _conversation.identifier) {
      // no need to show friend's name if your are in a personal chat box
      return null;
    }
    return ContentViewUtils.getNameLabel(sender);
  }

  String? _getCommandText(Content content, ID sender, IndexPath? indexPath) {
    String? text = ContentViewUtils.getCommandText(content, sender, _conversation);
    if (text != null && text.isNotEmpty && indexPath != null) {
      // if it's a command, check duplicate with next one
      if (indexPath.item > 0) {
        InstantMessage iMsg = _dataSource.getItem(indexPath.item - 1);
        String? next = _getCommandText(iMsg.content, iMsg.sender, null);
        if (next == text) {
          // duplicated, just keep the last one
          text = '';
        }
      }
    }
    return text;
  }
  Widget? _getCommandLabel(String text) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Expanded(flex: 1, child: Container()),
      Expanded(flex: 2,
        child: ContentViewUtils.getCommandLabel(text),
      ),
      Expanded(flex: 1, child: Container()),
    ],
  );

  Widget _getContentView(BuildContext ctx, Content content, ID sender) {
    if (content is ImageContent) {
      return ContentViewUtils.getImageContentView(ctx, content, sender, _dataSource.allMessages);
    } else if (content is AudioContent) {
      return ContentViewUtils.getAudioContentView(content, sender);
    } else if (content is VideoContent) {
      return ContentViewUtils.getVideoContentView(content, sender);
    } else {
      return ContentViewUtils.getTextContentView(content, sender);
    }
  }

  Widget _getContentFrame(BuildContext context, ID sender, int mainFlex, bool isMine,
      {required Widget image, Widget? name, required Widget body,
        required Widget? flag}) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (isMine)
        Expanded(flex: 1, child: Container()),
      if (!isMine)
        IconButton(
            padding: Styles.messageSenderAvatarPadding,
            onPressed: () => _openProfile(context, sender, _conversation),
            icon: image
        ),
      Expanded(flex: mainFlex, child: Column(
        crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (name != null)
            name,
          body,
          if (flag != null)
            flag,
        ],
      )),
      if (isMine)
        Container(
          padding: Styles.messageSenderAvatarPadding,
          child: image,
        ),
      if (!isMine)
        Expanded(flex: 1, child: Container()),
    ],
  );

}

class _HistoryDataSource {

  List<InstantMessage> _messages = [];

  List<InstantMessage> get allMessages => _messages;

  void refresh(List<InstantMessage> history) {
    Log.debug('refreshing ${history.length} message(s)');
    _messages = history;
  }

  int getItemCount() => _messages.length;

  InstantMessage getItem(int index) => _messages[index];
}

//--------

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
