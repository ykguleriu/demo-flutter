/* license: https://mit-license.org
 *
 *  DIM-SDK : Decentralized Instant Messaging Software Development Kit
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

import '../views/styles.dart';

class CupertinoTableCell extends StatelessWidget {
  const CupertinoTableCell({super.key, this.leadingSize = 60, this.leading,
    required this.title, this.subtitle,
    this.additionalInfo, this.trailing,
    this.onTap, this.onLongPress});

  final double leadingSize;
  final Widget? leading;
  final Widget title;
  final Widget? subtitle;
  final Widget? additionalInfo;
  final Widget? trailing;

  final GestureTapCallback? onTap;
  final GestureLongPressCallback? onLongPress;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    onLongPress: onLongPress,
    child: Column(
      children: [
        Container(
          padding: Styles.sectionItemPadding,
          color: Styles.sectionItemBackground,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _head(),
              Expanded(
                child: _body(),
              ),
              _additional(),
              _tail(),
            ],
          ),
        ),
        _divider(),
      ],
    ),
  );

  Widget _head() => Container(
    width: leading == null ? 16 : leadingSize,
    alignment: Alignment.center,
    child: leading,
  );

  Widget _body() => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      DefaultTextStyle(
        maxLines: 1,
        softWrap: false,
        style: Styles.sectionItemTitleTextStyle,
        child: title,
      ),
      if (subtitle != null)
        Container(
          padding: const EdgeInsets.only(top: 8),
          child: DefaultTextStyle(
            maxLines: 1,
            softWrap: false,
            style: Styles.sectionItemSubtitleTextStyle,
            child: subtitle!,
          ),
        ),
    ],
  );

  Widget _additional() => Container(
    padding: const EdgeInsets.fromLTRB(8, 8, 2, 8),
    child: DefaultTextStyle(
      style: Styles.sectionItemAdditionalTextStyle,
      child: additionalInfo ?? Container(),
    ),
  );

  Widget _tail() => Container(
    padding: const EdgeInsets.fromLTRB(2, 8, 8, 8),
    child: trailing ?? Container(),
  );

  Widget _divider() => Container(
    color: Styles.sectionItemBackground,
    child: Container(
      margin: leading == null ? null : EdgeInsetsDirectional.only(start: leadingSize),
      color: Styles.sectionItemDividerColor,
      height: 1,
    ),
  );

}
