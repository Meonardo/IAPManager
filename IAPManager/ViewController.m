//
//  ViewController.m
//  IAPManager
//
//  Created by Meonardo on 2017/8/21.
//  Copyright © 2017年 Meonardo. All rights reserved.
//

#import "ViewController.h"
#import "IAPManager.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

// 点击内购商品
- (void)clickIAP2Pay{
    NSString *productId = @"1"; //商品 Id (内购商品)
    NSString *userId = @"10086"; //在异常情况下, 需要保存购买凭证一遍下次验证 所以需要 userId 区分用户
    [IAPManager purchaseWithId:productId userId:userId completionBlock:^(IAPResultCode code, id info) {
        if (code == IAPResultCodeValidingWithServer){
            //[self checkReceiptIsValid:productId userId:userId receipt:info];//
            [IAPManager validReceiptWithAppStore:^(IAPResultCode code, id info) {// 测试 应用直接与 iTunesConnect 验证
                if (code == IAPResultCodeSuccess){
                    [IAPManager completePurchaseWithId:@"1" userId:@"10086" completionBlock:nil];
                }
            }];
        }
    }];
}

- (void)checkReceiptIsValid:(NSString *)productId userId:(NSString *)userId receipt:(NSData *)data{
    NSString *base64String = [data base64EncodedStringWithOptions:0];
    if (base64String){
//        [[EgretRuntime getInstance] callEgretInterface:@"mustPayInited" value:base64String];
    }
}

// 将购买凭证传给后端进行验证
- (void)validateWithServer{
    
}

@end
