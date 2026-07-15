#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Thin ObjC façade around `UEApi` so Swift can call completion-block APIs safely.
/// Simulator builds stub out (vendor binary is device arm64 only).
@interface UEPayObjCBridge : NSObject

+ (BOOL)isAvailable;

+ (void)configureWithLogo:(NSString *)logo
                storeName:(NSString *)storeName
                   scheme:(NSString *)scheme
                     beta:(BOOL)beta;

+ (BOOL)handleUEOpenURL:(NSURL *)url;

+ (void)combinedPayWithPaycode:(NSString *)paycode
                       orderNo:(NSString *)orderNo
                        target:(UIViewController *)target
                    completion:(void (^)(BOOL success, NSString * _Nullable message))completion;

@end

NS_ASSUME_NONNULL_END
