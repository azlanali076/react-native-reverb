//
//  RCTNativeReverb.h
//
//  Created by Syed Azlan Ali on 01/10/2025.
//

#import <Foundation/Foundation.h>
#import <NativeReverb/NativeReverb.h>
@class RCTBridge;
@protocol RCTBridgeModule;

NS_ASSUME_NONNULL_BEGIN

@interface RCTNativeReverb : NSObject <NativeReverbSpec>
@property (nonatomic, weak) RCTBridge *bridge;
@end

NS_ASSUME_NONNULL_END
