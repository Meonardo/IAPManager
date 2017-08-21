//
//  IAPManager.h
//  ZhaJinHuaIos
//
//  Created by Meonardo on 2017/8/18.
//  Copyright © 2017年 egret. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, IAPResultCode){
    IAPResultCodeIdle = 0,// 空闲状态
    IAPResultCodeSuccess, // 成功
    IAPResultCodeFailed, // 失败
    IAPResultCodeUserCanceled, //用户取消
    IAPResultCodeValidingWithServer, //与服务端验证购买凭证
    IAPResultCodeUnknown //未知错误 可见IAPCompletionBlock的 info 参数
};

typedef void(^IAPCompletionBlock)(IAPResultCode code, id info);

@interface IAPManager: NSObject

+ (instancetype)shared;

// 参数依次是: 内购商品 id, 用户 id, 此接口的回调(code 回调状态 id 其他信息)
+ (void)purchaseWithId:(NSString *)productId
                userId:(NSString *)userId
       completionBlock:(IAPCompletionBlock)completion;

// 从服务端验证完后需要删除本地存储的购买凭证
+ (void)completePurchaseWithId:(NSString *)productId
                        userId:(NSString *)userId
               completionBlock:(IAPCompletionBlock)completion;

// 检查没有和服务器验证的购买凭证
+ (void)checkIfLocalReceiptsNotValided:(IAPCompletionBlock)completion;

// 本地测试
+ (void)validReceiptWithAppStore:(IAPCompletionBlock)completion;

@end
