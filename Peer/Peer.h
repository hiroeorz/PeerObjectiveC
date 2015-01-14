/*
 * libjingle
 * Copyright 2014, Google Inc.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 *  1. Redistributions of source code must retain the above copyright notice,
 *     this list of conditions and the following disclaimer.
 *  2. Redistributions in binary form must reproduce the above copyright notice,
 *     this list of conditions and the following disclaimer in the documentation
 *     and/or other materials provided with the distribution.
 *  3. The name of the author may not be used to endorse or promote products
 *     derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR IMPLIED
 * WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO
 * EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
 * OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
 * WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
 * OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
 * ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import <Foundation/Foundation.h>

#import "RTCVideoTrack.h"
#import "RTCSessionDescription.h"
#import "RTCTypes.h"
#import "RTCEAGLVideoView.h"

typedef NS_ENUM(NSInteger, PeerClientState) {
  // Disconnected from servers.
  kPeerClientStateDisconnected,
  // Connecting to servers.
  kPeerClientStateConnecting,
  // Connected to servers.
  kPeerClientStateConnected,
};

@class Peer;

@interface Peer : NSObject

@property(nonatomic, readonly) PeerClientState state;
@property(nonatomic, strong) NSString *key;
@property(nonatomic, strong) NSString *id;
@property(nonatomic, strong) NSString *host;
@property(nonatomic, strong) NSString *path;
@property(nonatomic) BOOL secure;
@property(nonatomic) NSInteger port;
@property(nonatomic, strong) void(^onOpen)(NSString *id);
@property(nonatomic, strong) void(^onCall)(RTCSessionDescription *sdp);
@property(nonatomic, strong) void(^onClose)();
@property(nonatomic, strong) void(^onError)(NSError *error);
@property(nonatomic, strong) void(^onReceiveRemoteVideoTrack)(RTCVideoTrack *remoteVideoTrack);
@property(nonatomic, strong) void(^onReceiveLocalVideoTrack)(RTCVideoTrack *localVideoTrack);

- (instancetype)initWithConfig:(NSDictionary *)args;
- (void)start:(void (^)())block;
- (void)callWithId:(NSString*)dstId;
- (void)answerWithSdp:(RTCSessionDescription *)sdp;
- (void)disconnect;

@end
