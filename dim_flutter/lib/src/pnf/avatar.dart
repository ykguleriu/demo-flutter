/* license: https://mit-license.org
 *
 *  PNF : Portable Network File
 *
 *                               Written in 2023 by Moky <albert.moky@gmail.com>
 *
 * =============================================================================
 * The MIT License (MIT)
 *
 * Copyright (c) 2023 Albert Moky
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 * =============================================================================
 */
import 'package:flutter/cupertino.dart';

import 'package:dim_client/dim_client.dart';
import 'package:lnc/lnc.dart' as lnc;
import 'package:lnc/lnc.dart' show Log;

import '../client/shared.dart';
import '../common/constants.dart';
import '../filesys/local.dart';
import '../filesys/paths.dart';
import '../ui/icons.dart';
import '../ui/styles.dart';

import 'gallery.dart';
import 'image.dart';


/// preview avatar image
void previewAvatar(BuildContext context, ID identifier, PortableNetworkFile avatar) {
  var image = AvatarFactory().getImageView(identifier, avatar);
  Gallery([image], 0).show(context);
}


/// Factory for Avatar
class AvatarFactory {
  factory AvatarFactory() => _instance;
  static final AvatarFactory _instance = AvatarFactory._internal();
  AvatarFactory._internal();

  final Map<Uri, _AvatarImageLoader> _loaders = WeakValueMap();
  final Map<Uri, Set<_AvatarImageView>> _views = {};
  final Map<ID, Set<_AutoAvatarView>> _avatars = {};

  PortableImageLoader getImageLoader(PortableNetworkFile pnf) {
    _AvatarImageLoader? runner;
    Uri? url = pnf.url;
    if (url == null) {
      runner = _AvatarImageLoader(pnf);
      runner.run();
    } else {
      runner = _loaders[url];
      if (runner == null) {
        runner = _AvatarImageLoader(pnf);
        _loaders[url] = runner;
        runner.run();
      }
    }
    return runner;
  }

  PortableImageView getImageView(ID user, PortableNetworkFile pnf,
      {double? width, double? height}) {
    var loader = getImageLoader(pnf);
    Uri? url = pnf.url;
    if (url == null) {
      return _AvatarImageView(loader, user, width: width, height: height,);
    }
    _AvatarImageView? img;
    Set<_AvatarImageView>? table = _views[url];
    if (table == null) {
      table = WeakSet();
      _views[url] = table;
    } else {
      for (_AvatarImageView item in table) {
        if (item.width != width || item.height != height) {
          // size not match
        } else if (item.identifier != user) {
          // ID not match
        } else {
          // got it
          img = item;
          break;
        }
      }
    }
    if (img == null) {
      img = _AvatarImageView(loader, user, width: width, height: height,);
      table.add(img);
    }
    return img;
  }

  Widget getAvatarView(ID user, {double? width, double? height}) {
    width ??= 32;
    height ??= 32;
    _AutoAvatarView? avt;
    Set<_AutoAvatarView>? table = _avatars[user];
    if (table == null) {
      table = WeakSet();
      _avatars[user] = table;
    } else {
      for (_AutoAvatarView item in table) {
        if (item.width != width || item.height != height) {
          // size not match
        } else if (item.identifier != user) {
          // ID not match
        } else {
          // got it
          avt = item;
          break;
        }
      }
    }
    if (avt == null) {
      avt = _AutoAvatarView(user, width: width, height: height,);
      table.add(avt);
    }
    return avt;
  }

}

class _FacadeInfo {

  PortableImageView? avatarView;

}

/// Auto refresh avatar view
class _AutoAvatarView extends StatefulWidget {
  _AutoAvatarView(this.identifier, {required this.width, required this.height});

  final ID identifier;
  final double width;
  final double height;

  final _FacadeInfo _info = _FacadeInfo();

  @override
  State<StatefulWidget> createState() => _FacadeState();

}

class _FacadeState extends State<_AutoAvatarView> implements lnc.Observer {
  _FacadeState() {
    var nc = lnc.NotificationCenter();
    nc.addObserver(this, NotificationNames.kDocumentUpdated);
  }

  @override
  void dispose() {
    var nc = lnc.NotificationCenter();
    nc.removeObserver(this, NotificationNames.kDocumentUpdated);
    super.dispose();
  }

  @override
  Future<void> onReceiveNotification(lnc.Notification notification) async {
    String name = notification.name;
    Map? userInfo = notification.userInfo;
    if (name == NotificationNames.kDocumentUpdated) {
      ID? identifier = userInfo?['ID'];
      Document? visa = userInfo?['document'];
      assert(identifier != null && visa != null, 'notification error: $notification');
      if (identifier == widget.identifier && visa is Visa) {
        Log.info('document updated, refreshing facade: $identifier');
        // update refresh for new avatar
        await _reload();
      }
    } else {
      assert(false, 'should not happen');
    }
  }

  Future<void> _reload() async {
    ID identifier = widget.identifier;
    GlobalVariable shared = GlobalVariable();
    Visa? doc = await shared.facebook.getVisa(identifier);
    if (doc == null) {
      Log.warning('visa document not found: $identifier');
      return;
    }
    // get visa.avatar
    PortableNetworkFile? avatar = doc.avatar;
    if (avatar == null) {
      Log.warning('avatar not found: $doc');
      return;
    }
    var factory = AvatarFactory();
    var view = factory.getImageView(identifier, avatar,
        width: widget.width, height: widget.height);
    await view.loader.run();
    if (mounted) {
      setState(() {
        widget._info.avatarView = view;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    double width = widget.width;
    double height = widget.height;
    ID identifier = widget.identifier;
    Widget? view = widget._info.avatarView;
    view ??= _AvatarImageView.getNoImage(identifier, width: width, height: height);
    return ClipRRect(
      borderRadius: BorderRadius.all(
        Radius.elliptical(width / 8, height / 8),
      ),
      child: view,
    );
  }

}

class _AvatarImageView extends PortableImageView {
  const _AvatarImageView(super.loader, this.identifier, {this.width, this.height});

  final ID identifier;
  final double? width;
  final double? height;

  static Widget getNoImage(ID identifier, {double? width, double? height}) {
    double? size = width ?? height;
    if (identifier.type == EntityType.kStation) {
      return Icon(AppIcons.stationIcon, size: size, color: Styles.colors.avatarColor);
    } else if (identifier.type == EntityType.kBot) {
      return Icon(AppIcons.botIcon, size: size, color: Styles.colors.avatarColor);
    } else if (identifier.type == EntityType.kISP) {
      return Icon(AppIcons.ispIcon, size: size, color: Styles.colors.avatarColor);
    } else if (identifier.type == EntityType.kICP) {
      return Icon(AppIcons.icpIcon, size: size, color: Styles.colors.avatarColor);
    }
    if (identifier.isUser) {
      return Icon(AppIcons.userIcon, size: size, color: Styles.colors.avatarDefaultColor);
    } else {
      return Icon(AppIcons.groupIcon, size: size, color: Styles.colors.avatarDefaultColor);
    }
  }

}

class _AvatarImageLoader extends PortableImageLoader {
  _AvatarImageLoader(super.pnf);

  @override
  Widget getImage(PortableImageView view) {
    _AvatarImageView widget = view as _AvatarImageView;
    ID identifier = widget.identifier;
    double? width = widget.width;
    double? height = widget.height;
    var image = imageProvider;
    if (image == null) {
      return _AvatarImageView.getNoImage(identifier, width: width, height: height);
    } else if (width == null && height == null) {
      return Image(image: image,);
    } else {
      return Image(image: image, width: width, height: height, fit: BoxFit.cover,);
    }
  }

  @override
  Widget? getProgress(PortableImageView view) {
    _AvatarImageView widget = view as _AvatarImageView;
    double width = widget.width ?? 0;
    double height = widget.height ?? 0;
    if (width < 64 || height < 64) {
      return null;
    }
    return super.getProgress(view);
  }

  @override
  Future<String?> get temporaryDirectory async {
    LocalStorage cache = LocalStorage();
    String? dir = await cache.temporaryDirectory;
    if (dir == null) {
      return null;
    }
    return Paths.append(dir, 'download');
  }

  @override
  Future<String?> get cachesDirectory async {
    LocalStorage cache = LocalStorage();
    String? dir = await cache.cachesDirectory;
    if (dir == null) {
      return null;
    }
    return Paths.append(dir, 'avatar');
  }

}
