#import "UEPayObjCBridge.h"

#if !TARGET_OS_SIMULATOR
#import <UESDKProject/UEApi.h>
#endif

@implementation UEPayObjCBridge

+ (BOOL)isAvailable {
#if TARGET_OS_SIMULATOR
    return NO;
#else
    return NSClassFromString(@"UEApi") != nil;
#endif
}

+ (void)configureWithLogo:(NSString *)logo
                storeName:(NSString *)storeName
                   scheme:(NSString *)scheme
                     beta:(BOOL)beta {
#if !TARGET_OS_SIMULATOR
    UEApi *api = [UEApi sharedInstance];
    if (beta) {
        [api registBetaWithLogo:logo storeName:storeName Schemes:scheme];
    } else {
        [api registWithLogo:logo storeName:storeName Schemes:scheme];
    }
#else
    (void)logo; (void)storeName; (void)scheme; (void)beta;
#endif
}

+ (BOOL)handleUEOpenURL:(NSURL *)url {
#if !TARGET_OS_SIMULATOR
    return [[UEApi sharedInstance] handleOpenURL:url];
#else
    (void)url;
    return NO;
#endif
}

+ (void)combinedPayWithPaycode:(NSString *)paycode
                       orderNo:(NSString *)orderNo
                        target:(UIViewController *)target
                    completion:(void (^)(BOOL success, NSString * _Nullable message))completion {
#if TARGET_OS_SIMULATOR
    if (completion) {
        completion(NO, @"UE Pay SDK is device-only (not available on Simulator).");
    }
#else
    if (target == nil) {
        if (completion) {
            completion(NO, @"Missing view controller for UE Pay");
        }
        return;
    }
    [[UEApi sharedInstance] ueCombinedPayWithPaycode:paycode
                                             orderno:orderNo
                                              target:target
                                          completion:^(NSDictionary *result) {
        if (completion) {
            completion(YES, nil);
        }
        (void)result;
    } fail:^(NSInteger errorCode, NSString *errorMsg) {
        if (!completion) { return; }
        if (errorCode == UESDKCancel) {
            completion(NO, @"cancelled");
        } else {
            completion(NO, errorMsg.length > 0 ? errorMsg : [NSString stringWithFormat:@"UE Pay error (%ld)", (long)errorCode]);
        }
    }];
#endif
}

@end
