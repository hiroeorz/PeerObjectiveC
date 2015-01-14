# PeerObjectiveC

## About

<b>PeerObjectiveC</b> is WebRTC client library for iOS, that communicate to [peerjs-server](https://github.com/peers/peerjs-server).

This library is modified from the [AppRTCDemo](https://code.google.com/p/webrtc/source/browse/trunk/talk/examples/ios/?r=4466#ios%2FAppRTCDemo) (that Google has been published) for [peerjs-server](https://github.com/peers/peerjs-server) signaling process and [PeerJS](http://peerjs.com/) like API interface.

## Usage

### Build Sample App

1. Clone this repository.

    ```
    $ git clone https://github.com/hiroeorz/PeerObjectiveC.git
    ```

2. And build it on Xcode.

### Use PeerObjectiveC in your custom app.

1. Clone this repository.

    ```
    $ git clone https://github.com/hiroeorz/PeerObjectiveC.git
    ```
2. Copy ```Peer``` directory to your project, and add to your app on Xcode.

    ```
    $ cp -r PeerObjectiveC/Peer /path/to/yourapp/
    ```

3. You will need to add a few frameworks to your project in order for it to build correctly.
    * libc++.dylib
    * libicucore.dylib
    * Security.framework
    * CFNetwork.framework
    * GLKit.framework
    * libstdc++.6.dylib
    * AudioToolbox.framework
    * AVFoundation.framework
    * CoreAudio.framework
    * CoreMedia.framework
    * CoreVideo.framework
    * CoreGraphics.framework
    * OpenGLES.framework
    * QuartzCore.framework
    * libsqlite3.dylib

4. Initialize ```RTCPeerConnectionFactory``` in your AppDelegate.m

    AppDelegate.m

    ```objectivec
    #import "RTCPeerConnectionFactory.h"

    - (BOOL)application:(UIApplication *)application 
      didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
    {
        [RTCPeerConnectionFactory initializeSSL];
        return YES;
    }
    ```
5. And create instance of ```Peer``` class in ViewController.

    ViewController.m

    ```objectivec
    #import <AVFoundation/AVFoundation.h>
    #import "Peer.h"

    @interface ViewController () <RTCEAGLVideoViewDelegate>
    @property(nonatomic, strong) Peer *peer;
    @end

    @implementation ViewController {

    @synthesize peer = _peer;

    - (void)viewDidAppear:(BOOL)animate
    {
      __block typeof(self) __self = self;

      // Create Configuration object.
      NSDictionary *config = @{@"key": @"your_api_key", @"port": @(9000)};

      // Create Instance of Peer. 
      _peer = [[Peer alloc] initWithConfig:config];

      // Set Callbacks.
      _peer.onOpen = ^(NSString *id) {
        NSLog(@"onOpen");
      };
   
      _peer.onCall = ^(RTCSessionDescription *sdp) {
        NSLog(@"onCall");
      };

      _peer.onReceiveLocalVideoTrack = ^(RTCVideoTrack *videoTrack) {
        NSLog(@"onReceiveLocalVideoTrack");
      };

      _peer.onReceiveRemoteVideoTrack = ^(RTCVideoTrack *videoTrack) {
        NSLog(@"onReceiveRemoteVideoTrack");
      };

      _peer.onError = ^(NSError *error) {
        NSLog(@"onError: %@", error);
      };

      _peer.onClose = ^() {
        NSLog(@"onClose");
      };

      // Start signaling to peerjs-server.
      [_peer start:^(NSError *error){
        if (error) {
          NSLog(@"Error while openning websocket: %@", error);
        }
      }];
    }
    ``` 
    All default configuration is here.

    ```objectivec
    NSDictionary *config = @{@"host": @"0.peerjs.com",
                             @"port": @(80),
                             @"key": @"peerjs",
                             @"path": @"/",
                             @"secure": @(NO),
                             @"config": @{
                                 @"iceServers": @[
                                     @{@"url": @"stun:stun.l.google.com:19302", @"user": @"", @"password": @""}
                                 ]
                             }};
    ```
6. See example app, for more details.

## License

MIT
