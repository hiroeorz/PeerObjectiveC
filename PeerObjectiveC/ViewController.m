/*
 * libjingle
 * Copyright 2013, Google Inc.
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

#if !defined(__has_feature) || !__has_feature(objc_arc)
#error "This file requires ARC support."
#endif

#import "ViewController.h"

#import <AVFoundation/AVFoundation.h>
#import "Peer.h"

// Padding space for local video view with its parent.
static CGFloat const kLocalViewPadding = 20;

@interface ViewController () <RTCEAGLVideoViewDelegate>
@property(nonatomic, assign) UIInterfaceOrientation statusBarOrientation;
@property(nonatomic, strong) RTCEAGLVideoView* localVideoView;
@property(nonatomic, strong) RTCEAGLVideoView* remoteVideoView;
@property(nonatomic, strong) Peer *peer;
@property(nonatomic) BOOL isInitiater;
@end

@implementation ViewController {
  RTCVideoTrack* _localVideoTrack;
  RTCVideoTrack* _remoteVideoTrack;
  CGSize _localVideoSize;
  CGSize _remoteVideoSize;
}

@synthesize idField = _idField;
@synthesize isInitiater = _isInitiater;
@synthesize peer = _peer;

- (void)viewDidLoad
{
  [super viewDidLoad];

  self.remoteVideoView =
      [[RTCEAGLVideoView alloc] initWithFrame:self.blackView.bounds];
  self.remoteVideoView.delegate = self;
  self.remoteVideoView.transform = CGAffineTransformMakeScale(-1, 1);
  [self.blackView addSubview:self.remoteVideoView];

  self.localVideoView =
      [[RTCEAGLVideoView alloc] initWithFrame:self.blackView.bounds];
  self.localVideoView.delegate = self;
  [self.blackView addSubview:self.localVideoView];

  self.statusBarOrientation =
      [UIApplication sharedApplication].statusBarOrientation;
  self.roomInput.delegate = self;
  [self.roomInput becomeFirstResponder];

  _isInitiater = YES;
}

- (void)viewDidLayoutSubviews
{
  if (self.statusBarOrientation !=
      [UIApplication sharedApplication].statusBarOrientation) {
    self.statusBarOrientation =
        [UIApplication sharedApplication].statusBarOrientation;
    [[NSNotificationCenter defaultCenter]
        postNotificationName:@"StatusBarOrientationDidChange"
                      object:nil];
  }
}

- (void)viewDidAppear:(BOOL)animate
{
  if (!_isInitiater) { return; }
  [_peer disconnect];

  // full configurations.
  /*
  NSDictionary *config = @{@"host": @"0.peerjs.com",
                           @"port": @(9000),
                           @"key": @"peerjs",
                           @"path": @"/",
                           @"secure": @(NO),
                           @"config": @{
                               @"iceServers": @[
                                   @{@"url": @"stun:stun.l.google.com:19302", @"user": @"", @"password": @""}
                                   ]
                               }};
   */

  __block typeof(self) __self = self;
  NSDictionary *config = @{@"key": @"lwjd5qra8257b9", @"port": @(9000)};
  _peer = [[Peer alloc] initWithConfig:config];

  _peer.onOpen = ^(NSString *id) {
    NSLog(@"onOpen");
    __self.idField.text = id;
  };

  _peer.onCall = ^(RTCSessionDescription *sdp) {
    NSLog(@"onCall");
    [__self peerClient:__self.peer didReceiveOfferWithSdp:sdp];
  };

  _peer.onReceiveLocalVideoTrack = ^(RTCVideoTrack *videoTrack) {
    NSLog(@"onReceiveLocalVideoTrack");
    [__self peerClient:__self.peer didReceiveLocalVideoTrack:videoTrack];
  };

  _peer.onReceiveRemoteVideoTrack = ^(RTCVideoTrack *videoTrack) {
    NSLog(@"onReceiveRemoteVideoTrack");
    [__self peerClient:__self.peer didReceiveRemoteVideoTrack:videoTrack];
  };

  _peer.onError = ^(NSError *error) {
    NSLog(@"onError: %@", error);
    [__self peerClient:__self.peer didError:error];
  };

  _peer.onClose = ^() {
    NSLog(@"onClose");
    [__self resetUI];
  };

  [_peer start:^(NSError *error){
    if (error) {
      NSLog(@"Error while openning websocket: %@", error);
    }
  }];
}

- (void)applicationWillResignActive:(UIApplication*)application
{
  [self disconnect];
}

#pragma mark - ARDAppClientDelegate

- (void)peerClient:(Peer *)client didReceiveOfferWithSdp:(RTCSessionDescription *)sdp
{
  NSLog(@"setup CaptureSession!");
  _isInitiater = NO;
  [_roomInput resignFirstResponder];
  _roomInput.hidden = YES;
  self.instructionsView.hidden = YES;
  self.logView.hidden = NO;
  [self setupCaptureSession];

  [client answerWithSdp:sdp];
}

- (void)peerClient:(Peer *)client didReceiveLocalVideoTrack:(RTCVideoTrack *)localVideoTrack
{
  _localVideoTrack = localVideoTrack;
  [_localVideoTrack addRenderer:self.localVideoView];
  self.localVideoView.hidden = NO;
}

- (void)peerClient:(Peer *)client didReceiveRemoteVideoTrack:(RTCVideoTrack *)remoteVideoTrack
{
  _remoteVideoTrack = remoteVideoTrack;
  [_remoteVideoTrack addRenderer:self.remoteVideoView];
}

- (void)peerClient:(Peer *)client didError:(NSError *)error
{
  [self showAlertWithMessage:[NSString stringWithFormat:@"%@", error]];
  [self disconnect];
}

#pragma mark - RTCEAGLVideoViewDelegate

- (void)videoView:(RTCEAGLVideoView*)videoView didChangeVideoSize:(CGSize)size
{
  if (videoView == self.localVideoView) {
    _localVideoSize = size;
  } else if (videoView == self.remoteVideoView) {
    _remoteVideoSize = size;
  } else {
    NSParameterAssert(NO);
  }
  [self updateVideoViewLayout];
}

#pragma mark - UITextFieldDelegate

- (void)textFieldDidEndEditing:(UITextField*)textField
{
  NSString* dstId = textField.text;

  if ([dstId length] == 0) {
    return;
  }

  _isInitiater = YES;
  textField.hidden = YES;
  self.instructionsView.hidden = YES;
  self.logView.hidden = NO;
  [_peer callWithId:dstId];
  [self setupCaptureSession];
}

- (BOOL)textFieldShouldReturn:(UITextField*)textField
{
  // There is no other control that can take focus, so manually resign focus
  // when return (Join) is pressed to trigger |textFieldDidEndEditing|.
  [textField resignFirstResponder];
  return YES;
}

#pragma mark - Private

- (void)disconnect
{
  [self resetUI];
  [_peer disconnect];
}

- (void)showAlertWithMessage:(NSString*)message
{
  UIAlertView* alertView = [[UIAlertView alloc] initWithTitle:nil
                                                      message:message
                                                     delegate:nil
                                            cancelButtonTitle:@"OK"
                                            otherButtonTitles:nil];
  [alertView show];
}

- (void)resetUI
{
  [self.roomInput resignFirstResponder];
  self.roomInput.text = nil;
  self.roomInput.hidden = NO;
  self.logView.hidden = YES;
  self.logView.text = nil;

  if (_localVideoTrack) {
    [_localVideoTrack removeRenderer:self.localVideoView];
    _localVideoTrack = nil;
    [self.localVideoView renderFrame:nil];
  }

  if (_remoteVideoTrack) {
    [_remoteVideoTrack removeRenderer:self.remoteVideoView];
    _remoteVideoTrack = nil;
    [self.remoteVideoView renderFrame:nil];
  }

  self.blackView.hidden = YES;
}

- (void)setupCaptureSession
{
  self.blackView.hidden = NO;
  [self updateVideoViewLayout];
}

- (void)updateVideoViewLayout
{
  CGSize defaultAspectRatio = CGSizeMake(4, 3);
  CGSize localAspectRatio = CGSizeEqualToSize(_localVideoSize, CGSizeZero) ? defaultAspectRatio : _localVideoSize;
  CGSize remoteAspectRatio = CGSizeEqualToSize(_remoteVideoSize, CGSizeZero) ? defaultAspectRatio : _remoteVideoSize;

  CGRect remoteVideoFrame = AVMakeRectWithAspectRatioInsideRect(remoteAspectRatio, self.blackView.bounds);
  self.remoteVideoView.frame = remoteVideoFrame;

  CGRect localVideoFrame = AVMakeRectWithAspectRatioInsideRect(localAspectRatio, self.blackView.bounds);
  localVideoFrame.size.width = localVideoFrame.size.width / 3;
  localVideoFrame.size.height = localVideoFrame.size.height / 3;
  localVideoFrame.origin.x = CGRectGetMaxX(self.blackView.bounds) - localVideoFrame.size.width - kLocalViewPadding;
  localVideoFrame.origin.y = CGRectGetMaxY(self.blackView.bounds) - localVideoFrame.size.height - kLocalViewPadding;
  self.localVideoView.frame = localVideoFrame;
}

- (IBAction)finishCall:(id)sender
{
  [self disconnect];
}
@end
