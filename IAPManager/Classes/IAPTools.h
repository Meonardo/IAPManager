//
//  IAPTools.h
//  ZhaJinHuaIos
//
//  Created by Meonardo on 2017/8/18.
//  Copyright © 2017年 egret. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface IAPTools : NSObject

+ (NSString *)documentsDirectory;
+ (NSString *)encodeString:(NSString *)string;
+ (NSString *)decodeString:(NSString *)string;

@end

@interface IAPLoadingView : UIView

- (void)show;
- (void)dismiss;

@end
