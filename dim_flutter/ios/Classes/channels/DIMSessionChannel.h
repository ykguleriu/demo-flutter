//
//  DIMSessionChannel.h
//  Sechat
//
//  Created by Albert Moky on 2023/5/7.
//

#import <Flutter/Flutter.h>
#import <DIMClient/DIMClient.h>

NS_ASSUME_NONNULL_BEGIN

@interface DIMSessionChannel : FlutterMethodChannel

+ (instancetype)channelWithName:(NSString*)name
                binaryMessenger:(NSObject<FlutterBinaryMessenger>*)messenger
                          codec:(NSObject<FlutterMethodCodec>*)codec;

- (void)onStateChangedFrom:(nullable DIMSessionState *)previous
                        to:(nullable DIMSessionState *)current
                      when:(NSTimeInterval)now;

- (void)onReceivedData:(NSData *)pack from:(id<NIOSocketAddress>)remote;

@end

NS_ASSUME_NONNULL_END
