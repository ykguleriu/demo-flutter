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
import 'dart:io';
import 'dart:typed_data';

import 'package:dim_client/dim_client.dart';
import 'package:lnc/lnc.dart';

import '../common/constants.dart';
import '../channels/manager.dart';
import '../channels/session.dart';
import '../models/station.dart';
import '../client/shared.dart';

import 'station_speed.dart';

class VelocityMeter {
  VelocityMeter(this.info);

  final NeighborInfo info;

  String? socketAddress;  // '255.255.255.255:65535'

  String get host => info.host;
  int get port => info.port;
  ID? get identifier => info.identifier;
  double? get responseTime => info.responseTime;

  double _startTime = 0;

  @override
  String toString() {
    Type clazz = runtimeType;
    return '<$clazz host="$host", port=$port id="$identifier" rt=$responseTime />';
  }

  static Future<VelocityMeter> ping(NeighborInfo info) async {
    var nc = NotificationCenter();
    VelocityMeter meter = VelocityMeter(info);
    nc.postNotification(NotificationNames.kStationSpeedUpdated, meter, {
      'state': 'start',
      'meter': meter,
    });
    Socket? socket = await meter._connect(const Duration(seconds: 16));
    if (socket == null) {
      nc.postNotification(NotificationNames.kStationSpeedUpdated, meter, {
        'state': 'failed',
        'meter': meter,
      });
    } else {
      nc.postNotification(NotificationNames.kStationSpeedUpdated, meter, {
        'state': 'connected',
        'meter': meter,
      });
      double now = Time.currentTimeSeconds;
      double expired = now + 30;
      while (now < expired) {
        if (await meter._run()) {
          // task finished
          break;
        }
        await Future.delayed(const Duration(milliseconds: 128));
        now = Time.currentTimeSeconds;
      }
      nc.postNotification(NotificationNames.kStationSpeedUpdated, meter, {
        'state': 'finished',
        'meter': meter,
      });
      socket.destroy();
    }
    String host = meter.host;
    int port = meter.port;
    ID sid = meter.identifier ?? Station.kAny;
    DateTime now = DateTime.now();
    double rt = meter.responseTime ?? -1;
    String? socketAddress = meter.socketAddress;
    Log.info('station test result: $sid ($host:$port) - $rt, $socketAddress');
    // save the record
    GlobalVariable shared = GlobalVariable();
    await shared.database.addSpeed(host, port, identifier: sid,
        time: now, duration: rt, socketAddress: socketAddress);
    return meter;
  }

  Future<Socket?> _connect(Duration timeout) async {
    Uint8List? data = await _getPack();
    if (data == null) {
      assert(false, 'failed to get message package');
      return null;
    }
    Log.debug('connecting to $host:$port ...');
    _startTime = Time.currentTimeSeconds;
    Socket socket;
    try {
      socket = await Socket.connect(host, port, timeout: timeout);
    } on SocketException catch (e) {
      Log.error('failed to connect $host:$port, $e');
      return null;
    }
    // prepare data handler
    socket.listen((pack) async {
      Log.debug('received ${pack.length} bytes from $host:$port');
      _buffer.add(pack);
    }, onDone: () {
      Log.warning('speed task finished: $info');
      socket.destroy();
    });
    // send
    Log.debug('connected, sending ${data.length} bytes to $host:$port ...');
    socket.add(data);
    Log.debug('sent, waiting response from $host:$port ...');
    return socket;
  }

  final BytesBuilder _buffer = BytesBuilder(copy: false);
  int _start = 0;
  int _end = 0;

  Future<bool> _run() async {
    if (_end == _buffer.length) {
      // no new income data now
      return false;
    }
    Uint8List? pack = await _extract();
    while (pack != null) {
      if (await _process(pack)) {
        // done!
        return true;
      }
      pack = await _extract();
    }
    return false;
  }

  Future<Uint8List?> _extract() async {
    assert(_end <= _buffer.length, 'out of range: $_end, ${_buffer.length}');
    _end = _buffer.length;
    if (_start == _end) {
      // buffer empty
      return null;
    }
    assert(_start < _end, 'out of range: $_start, $_end');
    Uint8List pack = _buffer.toBytes().sublist(_start, _end);
    // MTP packing
    ChannelManager manager = ChannelManager();
    SessionChannel channel = manager.sessionChannel;
    Map? info = await channel.unpackData(pack);
    if (info == null) {
      Log.error('failed to unpack data: ${pack.length} bytes');
      return null;
    }
    int offset = info['position'];
    Log.error('position: $offset, pack length: ${pack.length}');
    if (offset <= 0) {
      // incomplete, waiting for more data
      return null;
    } else {
      _start += offset;
    }
    return info['payload'];
  }

  bool _checkMessageData(Uint8List data) {
    // {"sender":"","receiver":"","time":0,"data":"","signature":""}
    if (data.length < 64) {
      return false;
    }
    return data.first == _jsonStart && data.last == _jsonEnd;
  }
  final int _jsonStart = '{'.codeUnitAt(0);
  final int _jsonEnd   = '}'.codeUnitAt(0);

  Future<bool> _process(Uint8List data) async {
    if (!_checkMessageData(data)) {
      Log.warning('ignore pack: $data');
      return false;
    }
    GlobalVariable shared = GlobalVariable();
    ReliableMessage? rMsg = await shared.messenger?.deserializeMessage(data);
    // ReliableMessage? rMsg = await _decodeMsg(data);
    if (rMsg == null) {
      return false;
    }
    ID sender = rMsg.sender;
    if (sender.type != EntityType.kStation) {
      Log.error('sender not a station: $sender');
      return false;
    }
    double? duration = Time.currentTimeSeconds - _startTime;
    // OK
    info.identifier = sender;
    info.responseTime = duration;
    // fetch socket address
    try {
      socketAddress = await _decryptAddress(rMsg);
    } catch (e, st) {
      Log.error('socket address not found in message from $sender}, error: $e, $st');
    }
    Log.warning('station ($host:$port) $sender responded within $duration seconds via socket: "$socketAddress"');
    return true;
  }

  Future<String?> _decryptAddress(SecureMessage sMsg) async {
    GlobalVariable shared = GlobalVariable();
    InstantMessage? iMsg = await shared.messenger?.decryptMessage(sMsg);
    assert(iMsg != null, 'failed to decrypt message: ${sMsg.sender} => ${sMsg.receiver}');
    Content? content = iMsg?.content;
    var remote = content?['remote_address'];
    if (remote is List && remote.length == 2) {
      // 255.255.255.255:65535
      return '${remote.first}:${remote.last}';
    }
    return remote?.toString();
  }

}

Future<Uint8List?> _getPack() async {
  StationSpeeder speeder = StationSpeeder();
  Uint8List? data = await speeder.handshakePackage;
  if (data == null) {
    return null;
  }
  // MTP packing
  ChannelManager manager = ChannelManager();
  SessionChannel channel = manager.sessionChannel;
  Uint8List? pack = await channel.packData(data);
  Log.warning('packed ${data.length} bytes to ${pack?.length} bytes');
  return pack;
}
