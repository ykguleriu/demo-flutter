import 'package:flutter/cupertino.dart';

import 'package:dim_client/dim_client.dart';
import 'package:lnc/lnc.dart' as lnc;
import 'package:lnc/lnc.dart' show Log;

import '../client/constants.dart';
import '../client/group.dart';
import '../client/shared.dart';
import '../common/dbi/contact.dart';
import '../network/group_image.dart';

import '../widgets/alert.dart';
import 'amanuensis.dart';
import 'chat.dart';
import 'chat_contact.dart';


class Invitation {
  Invitation({required this.sender, required this.group, required this.member, required this.time});

  final ID sender;
  final ID group;
  final ID member;

  final DateTime? time;
}


class GroupInfo extends Conversation implements lnc.Observer {
  GroupInfo(super.identifier, {super.unread = 0, super.lastMessage, super.lastTime}) {
    var nc = lnc.NotificationCenter();
    nc.addObserver(this, NotificationNames.kDocumentUpdated);
    nc.addObserver(this, NotificationNames.kGroupHistoryUpdated);
  }

  @override
  Future<void> onReceiveNotification(lnc.Notification notification) async {
    String name = notification.name;
    Map? userInfo = notification.userInfo;
    if (name == NotificationNames.kDocumentUpdated) {
      ID? did = userInfo?['ID'];
      assert(did != null, 'notification error: $notification');
      if (did == identifier) {
        Log.info('document updated: $did');
        await reloadData();
      }
    } else if (name == NotificationNames.kGroupHistoryUpdated) {
      ID? did = userInfo?['ID'];
      assert(did != null, 'notification error: $notification');
      if (did == identifier) {
        Log.info('group history updated: $did');
        await reloadData();
      }
    } else {
      Log.error('notification error: $notification');
    }
  }

  ID? _current;

  String? _temporaryTitle;

  ID? _owner;
  List<ID>? _admins;
  List<ID>? _members;

  List<Invitation>? _invitations;
  Pair<ResetCommand?, ReliableMessage?>? _reset;

  /// owner
  bool get isOwner {
    ID? me = _current;
    ID? owner = _owner;
    return me != null && owner != null && me == owner;
  }
  bool get isNotOwner {
    ID? me = _current;
    ID? owner = _owner;
    return me != null && owner != null && me != owner;
  }

  /// administrator
  bool get isAdmin {
    ID? me = _current;
    List<ID>? admins = _admins;
    return me != null && admins != null && admins.contains(me);
  }
  bool get isNotAdmin {
    ID? me = _current;
    List<ID>? admins = _admins;
    return me != null && admins != null && !admins.contains(me);
  }

  /// member
  bool get isMember {
    ID? me = _current;
    List<ID>? members = _members;
    return me != null && members != null && members.contains(me);
  }
  bool get isNotMember {
    ID? me = _current;
    List<ID>? members = _members;
    return me != null && members != null && !members.contains(me);
  }

  /// Group Name
  @override
  String get title {
    String text = name;
    if (text.isEmpty) {
      text = _temporaryTitle ?? '';
    }
    // check alias in remark
    ContactRemark cr = remark;
    String alias = cr.alias;
    if (alias.isEmpty) {
      return text.isEmpty ? Anonymous.getName(identifier) : text;
    } else if (text.length > 15) {
      text = '${text.substring(0, 12)}...';
    }
    return '$text ($alias)';
  }

  ID? get owner => _owner;
  List<ID> get admins => _admins ?? [];
  List<ID> get members => _members ?? [];

  List<Invitation> get invitations => _invitations ?? [];
  Pair<ResetCommand?, ReliableMessage?> get reset => _reset ?? const Pair(null, null);

  @override
  Widget getImage({double? width, double? height, GestureTapCallback? onTap}) =>
      GroupImage(this, width: width, height: height, onTap: onTap);

  @override
  Future<void> reloadData() async {
    await super.reloadData();
    // check current user
    GlobalVariable shared = GlobalVariable();
    User? user = await shared.facebook.currentUser;
    assert(user != null, 'current user not found');
    ID? me = _current = user?.identifier;
    // check membership
    if (me == null) {
      _owner = null;
      _admins = null;
      _members = null;
    } else {
      /// owner
      _owner = await shared.facebook.getOwner(identifier);
      /// admins
      _admins = await shared.facebook.getAdministrators(identifier);
      /// members
      Document? doc = await shared.facebook.getDocument(identifier, '*');
      if (doc == null) {
        _members = null;
        _temporaryTitle = null;
      } else {
        List<ID> members = _members = await shared.facebook.getMembers(identifier);
        List<ContactInfo> users = [];
        ContactInfo? info;
        for (ID item in members) {
          info = ContactInfo.fromID(item);
          if (info == null) {
            Log.warning('failed to get contact: $item');
            continue;
          }
          users.add(info);
        }
        // check group name
        if (name.isEmpty && _temporaryTitle == null) {
          _temporaryTitle = await buildGroupName(members);
        }
        // post notification
        var nc = lnc.NotificationCenter();
        nc.postNotification(NotificationNames.kParticipantsUpdated, this, {
          'ID': identifier,
          'members': members,
        });
      }
    }
    if (_owner == null || _members == null) {
      _invitations = [];
      _reset = const Pair(null, null);
    } else {
      AccountDBI db = shared.facebook.database;
      List<Pair<GroupCommand, ReliableMessage>> histories = await db.getGroupHistories(group: identifier);
      GroupCommand content;
      ReliableMessage rMsg;
      List<Invitation> array = [];
      List<ID> members;
      for (var item in histories) {
        content = item.first;
        rMsg = item.second;
        assert(content.group == identifier, 'group ID not match: $identifier, $content');
        if (content is InviteCommand) {
          members = content.members ?? [];
        } else if (content is JoinCommand) {
          members = [rMsg.sender];
        } else {
          Log.warning('ignore group command: ${content.cmd}');
          continue;
        }
        Log.info('${rMsg.sender} invites $members');
        for (var user in members) {
          array.add(Invitation(
            sender: rMsg.sender,
            group: identifier,
            member: user,
            time: content.time ?? rMsg.time,
          ));
        }
      }
      _invitations = array;
      _reset = await db.getResetCommandMessage(group: identifier);
    }
  }

  static Future<String> buildGroupName(List<ID> members) async {
    assert(members.isNotEmpty, 'members should not be empty here');
    GlobalVariable shared = GlobalVariable();
    ClientFacebook facebook = shared.facebook;
    String text = await facebook.getName(members.first);
    String nickname;
    for (int i = 1; i < members.length; ++i) {
      nickname = await facebook.getName(members[i]);
      if (nickname.isEmpty) {
        continue;
      }
      text += ', $nickname';
      if (text.length > 32) {
        text = '${text.substring(0, 28)} ...';
        break;
      }
    }
    return text;
  }

  void setGroupName({required BuildContext context, required String name}) {
    // update memory
    if (name == this.name) {
      return;
    } else {
      this.name = name;
    }
    // save into document
    _updateGroupName(identifier, name).then((message) {
      if (message != null) {
        Alert.show(context, 'Error', message);
      }
    });
  }
  static Future<String?> _updateGroupName(ID group, String text) async {
    GlobalVariable shared = GlobalVariable();
    // 0. get local user
    User? user = await shared.facebook.currentUser;
    if (user == null) {
      assert(false, 'failed to get current user');
      return 'Failed to get current user.';
    }
    ID me = user.identifier;
    // 1. check permission
    GroupManager man = GroupManager();
    if (await man.dataSource.isOwner(me, group: group)) {
      Log.info('updating group $group by owner $me');
    } else {
      Log.error('cannot update group name: $group, $text');
      return 'Permission denied';
    }
    // 2. get old document
    Document? bulletin = await man.dataSource.getDocument(group, '*');
    if (bulletin == null) {
      // TODO: create a new bulletin?
      assert(false, 'failed to get group document: $group');
      return 'Failed to get group document';
    } else {
      // create new one for modifying
      Document? doc = Document.parse(bulletin.copyMap(false));
      assert(doc is Bulletin, 'failed to create bulletin document');
      bulletin = doc!;
    }
    // 2.1. get sign key for local user
    SignKey? sKey = await shared.facebook.getPrivateKeyForVisaSignature(me);
    if (sKey == null) {
      assert(false, 'failed to get sign key for user: $user');
      return 'Failed to get sign key';
    }
    // 2.2. update group name and sign it
    bulletin.name = text.trim();
    if (bulletin.sign(sKey) == null) {
      assert(false, 'failed to sign group document: $group');
      return 'Failed to sign group document';
    }
    // 3. save into local storage and broadcast it
    if (await man.dataSource.updateDocument(bulletin)) {
      Log.warning('group document updated: $group');
    } else {
      assert(false, 'failed to update group document: $group');
      return 'Failed to update group document';
    }
    // OK
    return null;
  }

  void quit({required BuildContext context}) {
    // check current user
    GlobalVariable shared = GlobalVariable();
    shared.facebook.currentUser.then((user) {
      if (user == null) {
        Log.error('current user not found, failed to add contact: $identifier');
        Alert.show(context, 'Error', 'Current user not found');
      } else {
        String msg = 'Are you sure to remove this group?\n'
            'This action will clear chat history too.';
        // confirm removing
        Alert.confirm(context, 'Confirm', msg,
          okAction: () => _doQuit(context, identifier, user.identifier),
        );
      }
    });
  }
  void _doQuit(BuildContext ctx, ID group, ID user) {
    // 1. quit group
    GroupManager man = GroupManager();
    man.quitGroup(group).then((out) {
      // 2. remove conversation
      Amanuensis clerk = Amanuensis();
      clerk.removeConversation(group);
      // 3. remove from contact list
      GlobalVariable shared = GlobalVariable();
      shared.database.removeContact(group, user: user);
      // OK
      Navigator.pop(ctx);
    }).onError((error, stackTrace) {
      Alert.show(ctx, 'Error', error.toString());
    });
  }

  static GroupInfo? fromID(ID identifier) =>
      identifier.isUser ? null :
      _ContactManager().getContact(identifier);

  static List<GroupInfo> fromList(List<ID> contacts) {
    List<GroupInfo> array = [];
    _ContactManager man = _ContactManager();
    for (ID item in contacts) {
      if (item.isUser) {
        Log.warning('ignore user conversation: $item');
        continue;
      }
      array.add(man.getContact(item));
    }
    return array;
  }

}

class _ContactManager {
  factory _ContactManager() => _instance;
  static final _ContactManager _instance = _ContactManager._internal();
  _ContactManager._internal();

  final Map<ID, GroupInfo> _contacts = {};

  GroupInfo getContact(ID identifier) {
    GroupInfo? info = _contacts[identifier];
    if (info == null) {
      info = GroupInfo(identifier);
      info.reloadData();
      _contacts[identifier] = info;
    }
    return info;
  }

}
