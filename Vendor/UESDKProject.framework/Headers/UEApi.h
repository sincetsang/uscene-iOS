//
//  UEApi.h
//  UETokenSDK
//
//  Created by osx on 2019/2/13.
//  Copyright © 2019年 osx. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN


/** 手动取消*/
static NSInteger UESDKCancel = 999;
/** 金额不足0.01*/
static NSInteger UESDKAmountLess  = 100;
/** 订单号为空*/
static NSInteger UESDKOrderNo  = 101;
/** 商品名称为空*/
static NSInteger UESDKProductName  = 102;
/** 父控制器为空*/
static NSInteger UESDKVC  = 202;
/**
 * @param nodeCode     返回nodeCode
 */
typedef void(^UEBindActionBlock)(NSString *nodeCode);
/**
 * @param result    返回result订单号
 */
typedef void(^UEPayCompletionBlock)(NSDictionary *result);
/**
 * @param result    返回授权结果
 */
typedef void(^UEAuthCompletionBlock)(NSInteger result,NSString *message,NSString *nodeId,NSString *nodeCode);

/**
 * @param errorCode    错误码
 * @param errorMsg     错误msg
 */
typedef void(^UEFailActionBlock)(NSInteger errorCode,
                               NSString *errorMsg);

@interface UEApi : NSObject

/**
 * 单例
 */
+ (instancetype)sharedInstance;
/**
 * SDK版本号1.0.5
 */
- (NSString *)currentVersion;
/**
 *  启动UESDK，在app启动时调用
 *
 *  @param logo                     设置第三方的logo，授权、绑定页面用到
 *  @param storeName          设置商家，授权、绑定页面用到
 *  @param schemes               设置app的schemes，用于app跳转
 */
- (void)registWithLogo:(NSString *)logo
            storeName:(NSString *)storeName
               Schemes:(NSString *)schemes;
/**
 *  启动UEBetaSDK，在app启动时调用
 *
 *  @param logo                 设置第三方的logo，授权、绑定页面用到
 *  @param storeName      设置商家，授权、绑定页面用到
 *  @param schemes           设置app的schemes，用于app跳转
 */
- (void)registBetaWithLogo:(NSString *)logo
                storeName:(NSString *)storeName
                  Schemes:(NSString *)schemes;
/**
 *  在APPDelegate相关方法里面调用，否则将无法跳回
 */
- (BOOL)handleOpenURL:(NSURL *)url;


#pragma mark -
/**
 *  调起绑定UE账户(码库APP服务端会做绑定关系)
 *  @param nodeCode          调用者的用户唯一标识
 *  @param currentVC        当前控制器
 *  @param completion      完成回调
 */
- (void)ueBindWithNodecode:(NSString *)nodeCode
     ueLoginWithCurrentVC:(UIViewController *)currentVC
               completion:(UEBindActionBlock)completion
                     fail:(UEFailActionBlock)fail;

/**
 *  调起UE 支付界面
 *  @param param                     生成参数的字典
 *  @param currentVC            当前控制器
 *  @param completion          完成回调
 */
- (void)uePayWithParam:(NSDictionary *)param
            currentVC:(UIViewController *)currentVC
           completion:(UEPayCompletionBlock)completion
                 fail:(UEFailActionBlock)fail;



/**
 *  调起UE组合支付界面
 *  @param paycode                      支付码
 *  @param orderno                      订单号
 *  @param target                        当前控制器
 *  @param completion               完成回调
 */
- (void)ueCombinedPayWithPaycode:(NSString *)paycode
                        orderno:(NSString *)orderno
                         target:(UIViewController *)target
                     completion:(UEPayCompletionBlock)completion
                           fail:(UEFailActionBlock)fail;

/**
 *  调起UE 免密授权界面
 *  @param nodeId                  nodeid
 *  @param nodeCode              nodeCode
 *  @param openType              码库分配给第三方的opentype（请咨询码库官方获取）
 *  @param currentVC            当前控制器
 *  @param completion          完成回调
*/
- (void)ueAvoidSecretAuthorizationWithNodeId:(NSString *)nodeId
                                   nodeCode:(NSString *)nodeCode
                                   openType:(NSInteger)openType
                                 currentVC:(UIViewController *)currentVC
                                completion:(UEAuthCompletionBlock)completion
                                      fail:(UEFailActionBlock)fail;

@end

NS_ASSUME_NONNULL_END
