//
//  RCTNativeReverb.m
//
//  Created by Syed Azlan Ali on 01/10/2025.
//

#import "NativeReverb.h"
#import <NativeReverb/NativeReverb.h>
#import <React/RCTBridge.h>
#import <React/RCTBridgeModule.h>


@interface RCTNativeReverb () <NSURLSessionWebSocketDelegate>
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSURLSessionWebSocketTask *webSocket;

@property (nonatomic, strong) NSString *socketId;
@property (nonatomic, strong) NSString *scheme;
@property (nonatomic, strong) NSString *url;
@property (nonatomic, strong) NSString *appKey;
@property (nonatomic, strong) NSString *authEndpoint;
@property (nonatomic, strong) NSDictionary<NSString * , NSString *> *authHeaders;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *listeners;
@end

@implementation RCTNativeReverb

+ (NSString *)moduleName { 
  return @"NativeReverb";
}

- (instancetype)init
{
  self = [super init];
  if (self) {
    self.listeners = [NSMutableDictionary new];
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    self.session = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:nil];
  }
  return self;
}

// Required for RCTEventEmitter
- (NSArray<NSString *> *)supportedEvents {
    return @[@"ReverbEvent"];
}

- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:(const facebook::react::ObjCTurboModule::InitParams &)params { 
  return std::make_shared<facebook::react::NativeReverbSpecJSI>(params);
}

- (void)connect:(nonnull RCTPromiseResolveBlock)resolve reject:(nonnull RCTPromiseRejectBlock)reject { 
  if(!self.url || !self.appKey || !self.scheme) {
    dispatch_async(dispatch_get_main_queue(), ^{
      reject(@"INVALID_CONFIG", @"URL, appKey, or scheme not set", nil);
    });
    return;
  }
  
  NSString *wsURLString = [NSString stringWithFormat:@"%@://%@/app/%@", self.scheme, self.url, self.appKey];
  NSURL *wsURL = [NSURL URLWithString:wsURLString];
  if (!wsURL) {
    dispatch_async(dispatch_get_main_queue(), ^{
      reject(@"INVALID_URL", @"Failed to create WebSocket URL", nil);
    });
      return;
  }
  NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:wsURL];
  [self.authHeaders enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
      [request setValue:value forHTTPHeaderField:key];
  }];
  self.webSocket = [self.session webSocketTaskWithRequest:request];
  [self.webSocket resume];
  
  __weak RCTNativeReverb *weakSelf = self;
  
  __block void (^receiveMessageBlock)(void);
  
    receiveMessageBlock = ^{
      __strong RCTNativeReverb *strongSelf = weakSelf;
      if (!strongSelf.webSocket) {
          return; // Stop recursion if socket disconnected
      }
      [strongSelf.webSocket receiveMessageWithCompletionHandler:^(NSURLSessionWebSocketMessage * _Nullable message, NSError * _Nullable error) {
        if (error) {
          NSLog(@"WebSocket receive error: %@", error);
//          dispatch_async(dispatch_get_main_queue(), ^{
//            reject(@"WEBSOCKET_ERROR", error.localizedDescription, error);
//          });
          return;
        }
        
        if (message.type == NSURLSessionWebSocketMessageTypeString) {
          NSString *text = message.string;
          
          // Force log immediately
          fprintf(stderr, "[WebSocket Message] %s\n", [text UTF8String]);
          fflush(stderr);
          NSDictionary *json = [NSJSONSerialization JSONObjectWithData:[text dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
          
          NSString *event = json[@"event"];
          if ([event isEqualToString:@"pusher:connection_established"]) {
            NSDictionary *data = [NSJSONSerialization JSONObjectWithData:[json[@"data"] dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
            weakSelf.socketId = data[@"socket_id"];
            dispatch_async(dispatch_get_main_queue(), ^{
              resolve(@"Connected to WebSocket!");
            });
          }
          
          if ([event isEqualToString:@"pusher:ping"]) {
            NSString *pongString = @"{\"event\":\"pusher:pong\"}";
            [weakSelf.webSocket sendMessage:[[NSURLSessionWebSocketMessage alloc] initWithString:pongString] completionHandler:^(NSError * _Nullable error) {
              if(error) {
                NSLog(@"WebSocket send error: %@", error);
              }
            }];
          }
          
          NSString *channel = json[@"channel"] ?: @"";
          NSString *eventName = json[@"event"] ?: @"";
          NSString *key = [NSString stringWithFormat:@"%@|%@", channel, eventName];
          if (weakSelf.listeners[key]) {
            [weakSelf sendEvent:channel event:eventName data:json[@"data"]];
          }
        }
        receiveMessageBlock();
      }];
    };
  
  receiveMessageBlock();
}

- (void)createClient:(JS::NativeReverb::NativeReverbOptions &)options {
  self.url = options.url();
  self.appKey = options.appKey();
  self.scheme = options.scheme();
  
  auto authOpt = options.auth();
  if (authOpt.has_value()) {
    auto auth = authOpt.value();
    if(auth.endpoint()){
      self.authEndpoint = auth.endpoint();
    }
    if(auth.headers()) {
      auto headersObj = auth.headers();
      if(headersObj && [headersObj isKindOfClass:[NSDictionary class]]) {
        self.authHeaders = (NSDictionary<NSString *, NSString *> *)headersObj;
      }
    }
  }
  if(!self.session) {
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    self.session = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:nil];
  }
}

- (void)disconnect:(nonnull RCTPromiseResolveBlock)resolve reject:(nonnull RCTPromiseRejectBlock)reject {
  if (self.webSocket) {
    // Remove all listeners
    [self.listeners removeAllObjects];
    
    // Close WebSocket gracefully
    [self.webSocket cancelWithCloseCode:NSURLSessionWebSocketCloseCodeGoingAway reason:[@"Goodbye" dataUsingEncoding:NSUTF8StringEncoding]];
    
    self.webSocket = nil;
    
    dispatch_async(dispatch_get_main_queue(), ^{
      resolve(@"WebSocket disconnected!");
    });
  } else {
    // WebSocket was already nil
    dispatch_async(dispatch_get_main_queue(), ^{
      resolve(@"WebSocket already disconnected!");
    });
  }
}

- (void)listen:(nonnull NSString *)channel event:(nonnull NSString *)event resolve:(nonnull RCTPromiseResolveBlock)resolve reject:(nonnull RCTPromiseRejectBlock)reject {
  if (!self.webSocket) {
    dispatch_async(dispatch_get_main_queue(), ^{
      reject(@"WEBSOCKET_NOT_CONNECTED", @"WebSocket is not connected", nil);
    });
    return;
  }

  NSString *key = [NSString stringWithFormat:@"%@|%@", channel, event];
  self.listeners[key] = @(YES);

  dispatch_async(dispatch_get_main_queue(), ^{
    resolve([NSString stringWithFormat:@"Listening on channel '%@', event '%@'", channel, event]);
  });
}

- (void)removeAllListeners:(nonnull NSString *)channel resolve:(nonnull RCTPromiseResolveBlock)resolve reject:(nonnull RCTPromiseRejectBlock)reject { 
  if (!self.webSocket) {
    dispatch_async(dispatch_get_main_queue(), ^{
      reject(@"WEBSOCKET_NOT_CONNECTED", @"WebSocket is not connected", nil);
    });
    return;
  }

  // Remove all listeners for this channel
  NSArray *keysToRemove = [self.listeners.allKeys filteredArrayUsingPredicate: [NSPredicate predicateWithBlock:^BOOL(NSString *key, NSDictionary *bindings) {
      return [key hasPrefix:[channel stringByAppendingString:@"|"]];
  }]];

  for (NSString *key in keysToRemove) {
      [self.listeners removeObjectForKey:key];
  }

  // Send unsubscribe message to the server
  NSDictionary *msg = @{@"event": @"pusher:unsubscribe",
                        @"data": @{@"channel": channel}};

  NSData *msgData = [NSJSONSerialization dataWithJSONObject:msg options:0 error:nil];
  NSURLSessionWebSocketMessage *message = [[NSURLSessionWebSocketMessage alloc] initWithData:msgData];

  [self.webSocket sendMessage:message completionHandler:^(NSError * _Nullable error) {
    if (error) {
      dispatch_async(dispatch_get_main_queue(), ^{
        reject(@"REMOVE_ALL_LISTENERS_ERROR", error.localizedDescription, error);
      });
    } else {
      dispatch_async(dispatch_get_main_queue(), ^{
        resolve([NSString stringWithFormat:@"Removed all listeners and unsubscribed from channel '%@'", channel]);
      });
    }
  }];
}

- (void)removeListener:(nonnull NSString *)channel event:(nonnull NSString *)event resolve:(nonnull RCTPromiseResolveBlock)resolve reject:(nonnull RCTPromiseRejectBlock)reject { 
  if (!self.webSocket) {
    dispatch_async(dispatch_get_main_queue(), ^{
      reject(@"WEBSOCKET_NOT_CONNECTED", @"WebSocket is not connected", nil);
    });
      return;
  }

  NSString *key = [NSString stringWithFormat:@"%@|%@", channel, event];
  [self.listeners removeObjectForKey:key];

  dispatch_async(dispatch_get_main_queue(), ^{
    resolve([NSString stringWithFormat:@"Stopped listening on channel '%@', event '%@'", channel, event]);
  });
}

- (void)subscribe:(nonnull NSString *)channel resolve:(nonnull RCTPromiseResolveBlock)resolve reject:(nonnull RCTPromiseRejectBlock)reject { 
  if (!self.webSocket) {
    dispatch_async(dispatch_get_main_queue(), ^{
      reject(@"WEBSOCKET_NOT_CONNECTED", @"WebSocket is not connected", nil);
    });
    return;
  }

  if ([channel hasPrefix:@"private-"]) {
    if (!self.authEndpoint) {
        dispatch_async(dispatch_get_main_queue(), ^{
          reject(@"AUTH_ENDPOINT_NOT_SET", @"No authEndpoint provided", nil);
        });
        return;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:self.authEndpoint]];
    request.HTTPMethod = @"POST";
    NSString *bodyString = [NSString stringWithFormat:@"channel_name=%@&socket_id=%@", channel, self.socketId];
    request.HTTPBody = [bodyString dataUsingEncoding:NSUTF8StringEncoding];

    for (NSString *key in self.authHeaders) {
        [request setValue:self.authHeaders[key] forHTTPHeaderField:key];
    }
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];

    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request
                                                 completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        if (error) {
          dispatch_async(dispatch_get_main_queue(), ^{
            reject(@"AUTH_FAILED", error.localizedDescription, error);
          });
          return;
        }
      
      NSString *rawResponse = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
      NSLog(@"Auth response: %@", rawResponse);  // <-- log this

        NSError *jsonError = nil;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        if (jsonError) {
          dispatch_async(dispatch_get_main_queue(), ^{
            reject(@"AUTH_FAILED", jsonError.localizedDescription, jsonError);
          });
          return;
        }

        NSString *authToken = json[@"auth"];
        if (!authToken) {
          dispatch_async(dispatch_get_main_queue(), ^{
            reject(@"AUTH_FAILED", @"No auth token returned", nil);
          });
          return;
        }

        [self sendSubscribeMessageToChannel:channel authToken:authToken resolve:resolve reject:reject];
    }];

    [task resume];
  } else {
      [self sendSubscribeMessageToChannel:channel authToken:nil resolve:resolve reject:reject];
  }
}

- (void)unsubscribe:(nonnull NSString *)channel resolve:(nonnull RCTPromiseResolveBlock)resolve reject:(nonnull RCTPromiseRejectBlock)reject {
  if (!self.webSocket) {
    dispatch_async(dispatch_get_main_queue(), ^{
      reject(@"WEBSOCKET_NOT_CONNECTED", @"WebSocket is not connected", nil);
    });
    return;
  }

  // Remove all listeners for this channel
  NSArray *keysToRemove = [self.listeners.allKeys filteredArrayUsingPredicate:
                           [NSPredicate predicateWithBlock:^BOOL(NSString *key, NSDictionary *bindings) {
    return [key hasPrefix:[channel stringByAppendingString:@"|"]];
  }]];

  for (NSString *key in keysToRemove) {
      [self.listeners removeObjectForKey:key];
  }

  NSDictionary *msg = @{@"event": @"pusher:unsubscribe",@"data": @{@"channel": channel}};

  NSData *msgData = [NSJSONSerialization dataWithJSONObject:msg options:0 error:nil];
  NSURLSessionWebSocketMessage *message = [[NSURLSessionWebSocketMessage alloc] initWithData:msgData];

  [self.webSocket sendMessage:message completionHandler:^(NSError * _Nullable error) {
      if (error) {
        dispatch_async(dispatch_get_main_queue(), ^{
          reject(@"UNSUBSCRIBE_ERROR", error.localizedDescription, error);
        });
      } else {
        dispatch_async(dispatch_get_main_queue(), ^{
          resolve([NSString stringWithFormat:@"Unsubscribed from channel '%@'", channel]);
        });
      }
  }];
}

- (void)sendSubscribeMessageToChannel:(NSString *)channel
                             authToken:(NSString * _Nullable)authToken
                              resolve:(RCTPromiseResolveBlock)resolve
                               reject:(RCTPromiseRejectBlock)reject
{
  NSMutableDictionary *data = [NSMutableDictionary dictionary];
  [data setObject:channel forKey:@"channel"];
  if (authToken) {
      [data setObject:authToken forKey:@"auth"];
  }

  NSDictionary *msg = @{@"event": @"pusher:subscribe", @"data": data};
  NSData *msgData = [NSJSONSerialization dataWithJSONObject:msg options:0 error:nil];
  NSURLSessionWebSocketMessage *message = [[NSURLSessionWebSocketMessage alloc] initWithData:msgData];

  [self.webSocket sendMessage:message completionHandler:^(NSError * _Nullable error) {
      if (error) {
        dispatch_async(dispatch_get_main_queue(), ^{
          reject(@"SUBSCRIBE_ERROR", error.localizedDescription, error);
        });
      } else {
        dispatch_async(dispatch_get_main_queue(), ^{
          resolve([NSString stringWithFormat:@"Subscribed to channel '%@'", channel]);
        });
      }
  }];
}


- (void)sendEvent:(NSString *)channel event:(NSString *)event data:(NSString *)data {
  if(self.bridge){
    [self.bridge enqueueJSCall:@"RCTDeviceEventEmitter" method:@"emit" args:@[@"ReverbEvent",@{@"channel":channel ?: @"",@"event":event ?: @"",@"data":data ?: @""}] completion:nil];
  }
  else {
    NSLog(@"Bridge not ready, dropping event %@|%@",channel,event);
  }
//  [self sendEventWithName:@"ReverbEvent" body:@{@"channel": channel, @"event": event, @"data": data}];
}

@end
