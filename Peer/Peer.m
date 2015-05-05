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

#import "Peer.h"

#import <AVFoundation/AVFoundation.h>
#import "ARDSignalingMessage.h"
#import "RTCICEServer.h"
#import "RTCMediaConstraints.h"
#import "RTCMediaStream.h"
#import "RTCPair.h"
#import "RTCPeerConnection.h"
#import "RTCPeerConnectionDelegate.h"
#import "RTCPeerConnectionFactory.h"
#import "RTCSessionDescriptionDelegate.h"
#import "RTCVideoCapturer.h"
#import "RTCVideoTrack.h"
#import "SRWebSocket.h"
#import "RTCICECandidate.h"

static NSString *kPeerClientErrorDomain = @"PeerJS";
static NSInteger kPeerClientErrorCreateSDP = -3;
static NSInteger kPeerClientErrorSetSDP = -4;

#define kMessageQueueCapacity 10
#define kDefaultHost @"0.peerjs.com"
#define kDefaultPath @"/"
#define kDefaultKey @"peerjs"
#define kWsURLTemplate @"%@://%@:%ld%@/peerjs?key=%@&id=%@&token=%@"
#define kDefaultSTUNServerUrl @"stun:stun.l.google.com:19302"

@interface Peer () <RTCPeerConnectionDelegate, RTCSessionDescriptionDelegate, SRWebSocketDelegate>

@property(nonatomic, strong) RTCPeerConnection *peerConnection;
@property(nonatomic, strong) RTCPeerConnectionFactory *factory;
@property(nonatomic, strong) NSMutableArray *messageQueue;
@property(nonatomic, strong) NSString *dstId;
@property(nonatomic, assign) BOOL isInitiator;
@property(nonatomic, strong) NSMutableArray *iceServers;
@property(nonatomic, strong) NSString *connectionId;
@property(nonatomic, strong) SRWebSocket *webSock;
@property(nonatomic, strong) void(^webSocketOpenCallBack)(NSString *connectionId, NSError *error);
@property(nonatomic) NSInteger cameraPosition;
@property(nonatomic, strong) RTCVideoTrack *localVideoTrack;
@property(nonatomic, strong) RTCMediaStream *localMediaStream;
@end

@implementation Peer

@synthesize state = _state;
@synthesize peerConnection = _peerConnection;
@synthesize factory = _factory;
@synthesize messageQueue = _messageQueue;
@synthesize dstId = _dstId;
@synthesize isInitiator = _isInitiator;
@synthesize iceServers = _iceServers;

@synthesize key = _key;
@synthesize id = _id;
@synthesize host = _host;
@synthesize port = _port;
@synthesize path = _path;
@synthesize secure = _secure;
@synthesize webSock = _webSock;
@synthesize connectionId = _connectionId;
@synthesize webSocketOpenCallBack = _webSocketOpenCallBack;
@synthesize cameraPosition = _cameraPosition;
@synthesize onOpen = _onOpen;
@synthesize onCall = _onCall;
@synthesize onClose = _onClose;
@synthesize onError = _onError;
@synthesize onReceiveRemoteVideoTrack = _onReceiveRemoteVideoTrack;
@synthesize onReceiveLocalVideoTrack = _onReceiveLocalVideoTrack;
@synthesize localVideoTrack = _localVideoTrack;
@synthesize localMediaStream = _localMediaStream;

- (instancetype)initWithConfig:(NSDictionary *)args {
    if (self = [super init]) {
      _factory = [[RTCPeerConnectionFactory alloc] init];
      _messageQueue = [[NSMutableArray alloc] initWithCapacity:kMessageQueueCapacity];
      _iceServers = [NSMutableArray arrayWithObject:[self defaultSTUNServer]];
      _id = nil;
      _path = kDefaultPath;
      _host = kDefaultHost;
      _key = kDefaultKey;
      _port = 0;
      _secure = NO;
      _webSock = nil;
      _isInitiator = NO;
      _cameraPosition = AVCaptureDevicePositionFront;
      _localVideoTrack = nil;
      _localMediaStream = nil;

      if ([args objectForKey:@"key"]   ) {_key = [args objectForKey:@"key"];}
      if ([args objectForKey:@"id"]    ) {_id = [args objectForKey:@"id"];}
      if ([args objectForKey:@"path"]  ) {_path = [args objectForKey:@"path"];}
      if ([args objectForKey:@"host"]  ) {_host = [args objectForKey:@"host"];}
      if ([args objectForKey:@"port"]  ) {_port = [[args objectForKey:@"port"] integerValue];}
      if ([args objectForKey:@"secure"]) {_secure = [[args objectForKey:@"secure"] boolValue];}
      if ([args objectForKey:@"config"]) {
        NSDictionary *config = [args objectForKey:@"config"];

        if ([config objectForKey:@"iceServers"]) {
          _iceServers = [self getIceServers:[config objectForKey:@"iceServers"]];
        }
      }

      if (_port == 0) { _port = _secure ? 443 : 80;}
      if ([@"/" isEqualToString:_path]) {_path = @"";}

      RTCMediaConstraints *constrains = [self defaultPeerConnectionConstraints];
      _peerConnection = [_factory peerConnectionWithICEServers:_iceServers constraints:constrains delegate:self];
  }
  return self;
}

- (void)dealloc {
  [self disconnect];
}

#pragma Initializer helper

- (NSMutableArray *)getIceServers:(NSArray *)iceServers
{
  NSMutableArray *servers = [[NSMutableArray alloc] init];
  for (NSDictionary *ice in iceServers) {
    NSString *urlStr = [ice objectForKey:@"url"];
    NSString *user = [ice objectForKey:@"user"];
    NSString *password = [ice objectForKey:@"password"];

    NSURL *stunURL = [NSURL URLWithString:urlStr];
    RTCICEServer *iceServer = [[RTCICEServer alloc] initWithURI:stunURL
                                                       username:user password:password];
    [servers addObject:iceServer];
  }

  return servers;
}

#pragma Peer API

- (void)start:(void (^)())block
{
  _webSocketOpenCallBack = block;

  if (_id == nil || [_id isMemberOfClass:[NSNull class]]) {
    //__block typeof(self) __self = self;
    [self getId:^(NSString *clientId) {
      [self openWebSocket];
    }];
  }
  else {
    [self openWebSocket];
  }
}

- (void)callWithId:(NSString*)dstId
{
  _dstId = dstId;
  _isInitiator = YES;
  _connectionId = [_id stringByAppendingString:[self randStringWithMaxLenght:20]];
  [self setupLocalMedia];
  [self sendOffer];
}

- (void)answerWithSdp:(RTCSessionDescription *)sdp
{
  [_peerConnection setRemoteDescriptionWithDelegate:self sessionDescription:sdp];
}

// pos is AVCaptureDevicePositionBack or AVCaptureDevicePositionFront.
- (void)setCaptureDevicePosition:(NSInteger)pos
{
  if (pos != AVCaptureDevicePositionBack && pos != AVCaptureDevicePositionFront) {
    NSString *errorMsg = [[NSString alloc] initWithFormat:@"Invalid CaptureDevicePosition: %ld", pos];
    @throw errorMsg;
  }

  _cameraPosition = pos;
}

#pragma API Helper

- (void)setupLocalMedia
{
  RTCMediaStream *localStream = [self createLocalMediaStream];
  [_peerConnection addStream:localStream];
}

#pragma mark - SRWebSocketDelegate

- (void)webSocketDidOpen:(SRWebSocket *)webSocket
{
  NSLog(@"WebSocket opened!");
  _isInitiator = NO;
}

- (void)webSocket:(SRWebSocket *)webSocket didReceiveMessage:(id)str
{
  NSLog(@"WebSocket receive message: %@", str);
  NSData *data = [str dataUsingEncoding:NSUTF8StringEncoding];
  NSMutableDictionary *message = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil];
  [self processSignalingMessage:message];
}

- (void)webSocket:(SRWebSocket *)webSocket didCloseWithCode:(NSInteger)code reason:(NSString *)reason wasClean:(BOOL)wasClean
{
  NSLog(@"WebSocket closed. reason:%@", reason);
  [self deleteLocalMediaStream];
  _state = kPeerClientStateDisconnected;
}

- (void)webSocket:(SRWebSocket *)webSocket didFailWithError:(NSError *)error
{
  NSLog(@"WebSocket Error: %@", error);
  _state = kPeerClientStateDisconnected;

  if (_onError) {
    _onError(error);
  }

  if (_onClose) {
    _onClose();
  }

  [self deleteLocalMediaStream];
}

#pragma process signaling messsage methods

- (void)processSignalingMessage:(NSDictionary *)message
{
  NSString *type = (NSString *)[message objectForKey:@"type"];

  if      ([@"OPEN" isEqualToString:type])      {[self processOpenWithMessage:message];}
  else if ([@"CANDIDATE" isEqualToString:type]) {[self processCandidateWithMessage:message];}
  else if ([@"OFFER" isEqualToString:type])     {[self processOfferWithMessage:message];}
  else if ([@"ANSWER" isEqualToString:type])    {[self processAnswerWithMessage:message];}
  else if ([@"LEAVE" isEqualToString:type])     {[self processLeaveWithMessage:message];}
}

- (void)processOpenWithMessage:(NSDictionary *)message
{
  NSLog(@"Open connection Signaling server done.");

  _state = kPeerClientStateConnected;
  [self drainMessages];

  if (_onOpen) {
    _onOpen(_id);
  }
}

- (void)processCandidateWithMessage:(NSDictionary *)message
{
  NSDictionary *payload = [message objectForKey:@"payload"];
  NSDictionary *candidateObj = [payload objectForKey:@"candidate"];
  NSString *candidateMessage = [candidateObj objectForKey:@"candidate"];
  NSInteger sdpMLineIndex = [[candidateObj objectForKey:@"sdpMLineIndex"] integerValue];
  NSString *sdpMid = [candidateObj objectForKey:@"sdpMid"]; NSLog(@"remote candidate: %@", candidateObj);
  RTCICECandidate *candidate = [[RTCICECandidate alloc] initWithMid:sdpMid index:sdpMLineIndex sdp:candidateMessage];
  [_peerConnection addICECandidate:candidate];
}

- (void)processOfferWithMessage:(NSDictionary *)message
{
  _isInitiator = NO;
  NSDictionary *payload = [message objectForKey:@"payload"];
  NSDictionary *sdpObj = [payload objectForKey:@"sdp"];
  NSString *sdpMessage = [sdpObj objectForKey:@"sdp"];
  NSString *connectionType = [payload objectForKey:@"type"];
  _connectionId = [payload objectForKey:@"connectionId"];
  _dstId = [message objectForKey:@"src"];

  if ([@"media" isEqualToString:connectionType]) {
    NSLog(@"connectionType: %@", connectionType);
    [self setupLocalMedia];
    RTCSessionDescription *sdp = [[RTCSessionDescription alloc] initWithType:@"offer" sdp:sdpMessage];
    if(_onCall) { _onCall(sdp); }
  }
}

- (void)processAnswerWithMessage:(NSDictionary *)message
{
  NSDictionary *payload = [message objectForKey:@"payload"];
  NSDictionary *sdpObj = [payload objectForKey:@"sdp"];
  NSString *sdpMessage = [sdpObj objectForKey:@"sdp"]; NSLog(@"remote sdp: %@", sdpMessage);
  RTCSessionDescription *sdp = [[RTCSessionDescription alloc] initWithType:@"answer" sdp:sdpMessage];
  [_peerConnection setRemoteDescriptionWithDelegate:self sessionDescription:sdp];
}

- (void)processLeaveWithMessage:(NSDictionary *)message
{
  [self disconnect];
}

# pragma --

- (void)disconnect
{
  if (_state == kPeerClientStateDisconnected) {
    return;
  }

  [_peerConnection close];

  _dstId = nil;
  _isInitiator = NO;
  _messageQueue = [NSMutableArray array];
  _peerConnection = nil;
  _state = kPeerClientStateDisconnected;
  [_webSock close];
}

#pragma mark - RTCPeerConnectionDelegate

- (void)peerConnection:(RTCPeerConnection *)peerConnection
    signalingStateChanged:(RTCSignalingState)stateChanged {
  NSLog(@"Signaling state changed: %d", stateChanged);
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection
           addedStream:(RTCMediaStream *)stream {
  dispatch_async(dispatch_get_main_queue(), ^{
    NSLog(@"Received %lu video tracks and %lu audio tracks",
        (unsigned long)stream.videoTracks.count,
        (unsigned long)stream.audioTracks.count);
    if (stream.videoTracks.count) {
      RTCVideoTrack *videoTrack = stream.videoTracks[0];

      if (_onReceiveRemoteVideoTrack) {
        _onReceiveRemoteVideoTrack(videoTrack);
      }
    }
  });
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection
        removedStream:(RTCMediaStream *)stream {
  NSLog(@"Stream was removed.");
}

- (void)peerConnectionOnRenegotiationNeeded:
    (RTCPeerConnection *)peerConnection {
  NSLog(@"WARNING: Renegotiation needed but unimplemented.");
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection
    iceConnectionChanged:(RTCICEConnectionState)newState {
  NSLog(@"ICE state changed: %d", newState);

  switch (newState) {
    case RTCICEConnectionDisconnected:
      NSLog(@"ICE disconnected.");
      if (_onClose) { _onClose(); }
      break;
    case RTCICEConnectionClosed:
      NSLog(@"ICE closed.");
      if (_onClose) { _onClose(); }
      break;
    default:
        break;
  }
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection
    iceGatheringChanged:(RTCICEGatheringState)newState {
  NSLog(@"ICE gathering state changed: %d", newState);
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection
       gotICECandidate:(RTCICECandidate *)candidate {
  dispatch_async(dispatch_get_main_queue(), ^{
    [self sendCandidateWithMessage:candidate];
  });
}

- (void)peerConnection:(RTCPeerConnection*)peerConnection
    didOpenDataChannel:(RTCDataChannel*)dataChannel
{
  NSLog(@"Data Channel opened.");
}

#pragma mark - RTCSessionDescriptionDelegate

- (void)peerConnection:(RTCPeerConnection *)peerConnection
    didCreateSessionDescription:(RTCSessionDescription *)sdp
                          error:(NSError *)error {

  dispatch_async(dispatch_get_main_queue(), ^{
    if (error) {
      NSLog(@"Failed to create session description. Error: %@", error);
      [self disconnect];

      NSDictionary *userInfo = @{
        NSLocalizedDescriptionKey: @"Failed to create session description.",
      };

      NSError *sdpError = [[NSError alloc] initWithDomain:kPeerClientErrorDomain
                                                     code:kPeerClientErrorCreateSDP
                                                 userInfo:userInfo];
      if (_onError){ _onError(sdpError); }
      return;
    }

    [_peerConnection setLocalDescriptionWithDelegate:self
                                  sessionDescription:sdp];
    if (_isInitiator) {
      [self sendOfferMessage:sdp.description];
    }
    else {
      [self sendAnswerMessage:sdp.description];
    }
  });
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection
    didSetSessionDescriptionWithError:(NSError *)error {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (error) {
      NSLog(@"Failed to set session description. Error: %@", error);
      [self disconnect];
      NSDictionary *userInfo = @{
        NSLocalizedDescriptionKey: @"Failed to set session description.",
      };
      NSError *sdpError = [[NSError alloc] initWithDomain:kPeerClientErrorDomain
                                                     code:kPeerClientErrorSetSDP
                                                 userInfo:userInfo];
      if (_onError){ _onError(sdpError); }
      return;
    }

    if (!_isInitiator && !_peerConnection.localDescription) {
      RTCMediaConstraints *constraints = [self defaultAnswerConstraints];
      [_peerConnection createAnswerWithDelegate:self constraints:constraints];
    }
  });
}

#pragma mark - Private

- (void)sendOffer {
  [_peerConnection createOfferWithDelegate:self
                               constraints:[self defaultOfferConstraints]];
}

- (void)sendOfferMessage:(NSString *)sdpStr
{
  NSLog(@"sdp: %@", sdpStr);
  NSDictionary *message = @{@"type": @"OFFER",
                            @"src": _id,
                            @"dst": _dstId,
                            @"payload":
                              @{@"browser": @"Chrome",
                                @"serialization": @"binary",
                                @"type": @"media",
                                @"connectionId": _connectionId,
                                @"sdp": @{@"sdp": sdpStr, @"type": @"offer"} }
                            };
  [self sendMessage:message];
}

- (void)sendAnswerMessage:(NSString *)sdpStr
{
  NSLog(@"sdp: %@", sdpStr);
  NSDictionary *message = @{@"type": @"ANSWER",
                            @"src": _id,
                            @"dst": _dstId,
                            @"payload":
                              @{@"browser": @"Chrome",
                                @"serialization": @"binary",
                                @"type": @"media",
                                @"connectionId": _connectionId,
                                @"sdp": @{@"sdp": sdpStr, @"type": @"answer"} }
                            };

  [self sendMessage:message];
}

- (void)sendCandidateWithMessage:(RTCICECandidate *)candidate
{
  NSDictionary *candidateObj = @{@"sdpMLineIndex": @(candidate.sdpMLineIndex),
                                 @"sdpMid": candidate.sdpMid,
                                 @"candidate": candidate.sdp};

  NSDictionary *message = @{@"type": @"CANDIDATE",
                            @"src": _id,
                            @"dst": _dstId,
                            @"payload": @{
                                @"type": @"media",
                                @"connectionId": _connectionId,
                                @"candidate": candidateObj}
                            };

  [self sendMessage:message];
}



- (void)sendMessage:(NSDictionary *)message
{
  NSData *data = [NSJSONSerialization dataWithJSONObject:message options:0 error:nil];
  [_messageQueue addObject:data];
  [self drainMessages];
}

- (void)drainMessages
{
  if (_state != kPeerClientStateConnected) {
    return;
  }
  for (NSDictionary *msg in _messageQueue) {
      [_webSock send:msg];
  }
  _messageQueue = [[NSMutableArray alloc] initWithCapacity:kMessageQueueCapacity];
}

- (RTCMediaStream *)createLocalMediaStream {
  RTCMediaStream* localStream = [_factory mediaStreamWithLabel:@"ARDAMS"];
  RTCVideoTrack* localVideoTrack = nil;

  // The iOS simulator doesn't provide any sort of camera capture
  // support or emulation (http://goo.gl/rHAnC1) so don't bother
  // trying to open a local stream.
  // TODO(tkchin): local video capture for OSX. See
  // https://code.google.com/p/webrtc/issues/detail?id=3417.
#if !TARGET_IPHONE_SIMULATOR && TARGET_OS_IPHONE
  NSString *cameraID = nil;
  for (AVCaptureDevice *captureDevice in
       [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo]) {
    if (captureDevice.position == _cameraPosition) {
      cameraID = [captureDevice localizedName];
      break;
    }
  }
  NSAssert(cameraID, @"Unable to get the camera id");

  RTCVideoCapturer *capturer = [RTCVideoCapturer capturerWithDeviceName:cameraID];
  RTCMediaConstraints *mediaConstraints = [self defaultMediaStreamConstraints];
  RTCVideoSource *videoSource = [_factory videoSourceWithCapturer:capturer
                                                      constraints:mediaConstraints];
  localVideoTrack = [_factory videoTrackWithID:@"ARDAMSv0" source:videoSource];

  if (localVideoTrack) {
    [localStream addVideoTrack:localVideoTrack];
  }

  if (_onReceiveLocalVideoTrack) {
    _onReceiveLocalVideoTrack(localVideoTrack);
  }

#endif
  [localStream addAudioTrack:[_factory audioTrackWithID:@"ARDAMSa0"]];
  _localVideoTrack = localVideoTrack;
  _localMediaStream = localStream;
  return localStream;
}

/**
 * @brief ローカルのビデオストリームを削除する
 */
- (void)deleteLocalMediaStream {
  NSLog(@"deleteLocalMediaStream");

  if (_localMediaStream != nil && _localVideoTrack != nil) {
    [_localMediaStream removeVideoTrack:_localVideoTrack];
    _localVideoTrack = nil;
    NSLog(@"local video track remove from media stream");
  }
}

#pragma mark - Defaults

- (RTCMediaConstraints *)defaultMediaStreamConstraints {
  RTCMediaConstraints* constraints =
      [[RTCMediaConstraints alloc]
          initWithMandatoryConstraints:nil
                   optionalConstraints:nil];
  return constraints;
}

- (RTCMediaConstraints *)defaultAnswerConstraints {
  return [self defaultOfferConstraints];
}

- (RTCMediaConstraints *)defaultOfferConstraints {
  NSArray *mandatoryConstraints = @[
      [[RTCPair alloc] initWithKey:@"OfferToReceiveAudio" value:@"true"],
      [[RTCPair alloc] initWithKey:@"OfferToReceiveVideo" value:@"true"]
  ];
  RTCMediaConstraints* constraints =
      [[RTCMediaConstraints alloc]
          initWithMandatoryConstraints:mandatoryConstraints
                   optionalConstraints:nil];
  return constraints;
}

- (RTCMediaConstraints *)defaultPeerConnectionConstraints {
  NSArray *optionalConstraints = @[
      [[RTCPair alloc] initWithKey:@"DtlsSrtpKeyAgreement" value:@"true"]
  ];
  RTCMediaConstraints* constraints =
      [[RTCMediaConstraints alloc]
          initWithMandatoryConstraints:nil
                   optionalConstraints:optionalConstraints];
  return constraints;
}

- (RTCICEServer *)defaultSTUNServer {
  NSURL *defaultSTUNServerURL = [NSURL URLWithString:kDefaultSTUNServerUrl];
  return [[RTCICEServer alloc] initWithURI:defaultSTUNServerURL
                                  username:@"" password:@""];
}

#pragma Internal Methods

- (NSURL *)wsURL
{
  NSString *proto = _secure ? @"wss" : @"ws";
  NSString *token = [self randStringWithMaxLenght:34];
  NSString *urlStr = [NSString stringWithFormat:kWsURLTemplate,
                      proto, _host,  (long)_port, _path, _key, _id, token];
  NSLog(@"WebSocket URL: %@", urlStr);
  NSURL *url = [NSURL URLWithString:urlStr];
  return url;
}

- (void)openWebSocket
{
  _state = kPeerClientStateConnecting;
  NSURL *url = [self wsURL];
  _webSock = [[SRWebSocket alloc] initWithURL:url];
  [_webSock setDelegate:self];
  [_webSock open];
}

- (void)getId:(void (^)(NSString *clientId))block
{
  dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
  dispatch_queue_t main_queue = dispatch_get_main_queue();

  dispatch_async(queue, ^{
    NSString *proto = _secure ? @"https" : @"http";
    NSString *urlStr = [[NSString alloc] initWithFormat:@"%@://%@:%ld%@/%@/id", proto, _host, (long)_port, _path, _key];
    NSLog(@"API URL: %@", urlStr);
    NSURL *url = [NSURL URLWithString:urlStr];
    NSString *clientId = [[NSString alloc] initWithContentsOfURL:url encoding:NSUTF8StringEncoding error:nil];
    NSLog(@"clientId: %@", clientId);

    dispatch_async(main_queue, ^{
      _id = clientId;
      if (block) { block(clientId); }
    });
  });
}

// ランダムな長さのランダムな文字列を作る
- (NSString *)randStringWithMaxLenght:(NSInteger)len
{
  NSInteger length = [self randBetween:len max:len];
  unichar letter[length];
  for (int i = 0; i < length; i++) {
    letter[i] = [self randBetween:65 max:90];
  }
  return [[[NSString alloc] initWithCharacters:letter length:length] lowercaseString];
}

- (NSInteger)randBetween:(NSInteger)min max:(NSInteger)max
{
  return (random() % (max - min + 1)) + min;
}

@end
