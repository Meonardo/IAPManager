//
//  IAPManager.m
//  ZhaJinHuaIos
//
//  Created by Meonardo on 2017/8/18.
//  Copyright © 2017年 egret. All rights reserved.
//

#import "IAPManager.h"
#import <StoreKit/StoreKit.h>
#import "IAPTools.h"

#define kReceipt @"RECEIPT"
#define kFileExt @"receipt"

typedef void(^AlertResponseHandle)(NSInteger index);

@interface UIViewController (DisplayAlert)

- (void)showAlertWithTitle:(NSString *)title
                   message:(NSString *)message
            preferredStyle:(UIAlertControllerStyle)preferredStyle
            responseHandle:(AlertResponseHandle)handle
        cancelActionAtLast:(BOOL)cancelActionAtLast
              buttonTitles:(NSString *)buttonTitle, ... NS_REQUIRES_NIL_TERMINATION;

@end

@implementation UIViewController (DisplayAlert)

- (void)showAlertWithTitle:(NSString *)title
                   message:(NSString *)message
            preferredStyle:(UIAlertControllerStyle)preferredStyle
            responseHandle:(AlertResponseHandle)handle
        cancelActionAtLast:(BOOL)cancelActionAtLast
              buttonTitles:(NSString *)buttonTitle, ... NS_REQUIRES_NIL_TERMINATION{
    
    NSAssert(self, @"ViewContoller is NIL");
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:preferredStyle];
    
    va_list list;
    va_start(list, buttonTitle);
    void (^actionHandle)(NSInteger index) = ^void(NSInteger index){
        handle(index);
    };
    
    UIAlertAction *action = [UIAlertAction actionWithTitle:buttonTitle style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        actionHandle(1);
    }];
    [alertController addAction:action];
    
    NSString *argument;
    NSInteger count = 1;
    while ((argument = va_arg(list, NSString *))){
        if (argument){
            count ++;
            UIAlertAction *action = [UIAlertAction actionWithTitle:argument style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                actionHandle(count);
            }];
            [alertController addAction:action];
        }
    }
    va_end(list);
    
    if (cancelActionAtLast){
        UIAlertAction *cancleAction = [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
            actionHandle(0);// 0为取消
            [alertController dismissViewControllerAnimated:true completion:nil];
        }];
        [alertController addAction:cancleAction];
    }
    
    [self presentViewController:alertController animated:true completion:nil];
}

@end

@interface IAPManager ()<SKProductsRequestDelegate>

@property (nonatomic, copy) IAPCompletionBlock completionBlock;
@property (nonatomic, strong) NSString *productId;
@property (nonatomic, strong) NSString *userId;
@property (nonatomic, strong) NSData *receipt;// 本次购买凭证

@property (nonatomic, strong) IAPLoadingView *loadingView;
@property (nonatomic, strong) NSOperationQueue *ioQueue;
@property (nonatomic, strong, readonly) NSString *filePathBase;

@end

@implementation IAPManager

+ (instancetype)shared{
    static IAPManager *shared;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[IAPManager alloc] init];
    });
    return shared;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        [[NSFileManager defaultManager] createDirectoryAtPath:[self filePathBase] withIntermediateDirectories:true attributes:nil error:nil];
        [[SKPaymentQueue defaultQueue] addTransactionObserver:(id)self];
    }
    return self;
}

- (IAPLoadingView *)loadingView{
    if (!_loadingView) {
        _loadingView = [[[NSBundle mainBundle] loadNibNamed:@"IAPLoadingView" owner:self options:nil] firstObject];
        return _loadingView;
    }
    return _loadingView;
}

- (NSOperationQueue *)ioQueue{
    if (!_ioQueue){
        _ioQueue = [[NSOperationQueue alloc] init];
        _ioQueue.name = @"IAP_IO_QUEUE";
    }
    return _ioQueue;
}

- (NSString *)filePathBase{
    NSString *path = [NSString stringWithFormat:@"%@/%@", [IAPTools documentsDirectory], kReceipt];
    return path;
}

- (UIWindow *)window{
    return [[UIApplication sharedApplication] keyWindow];
}

#pragma mark - Public

+ (void)purchaseWithId:(NSString *)productId
                userId:(NSString *)userId
       completionBlock:(IAPCompletionBlock)completion{
    [[IAPManager shared] purchaseWithId:productId
                                 userId:(NSString *)userId
                        completionBlock:completion];
}

+ (void)checkIfLocalReceiptsNotValided:(IAPCompletionBlock)completion{
    [[IAPManager shared] checkIfLocalReceiptsNotValided:completion];
}

+ (void)completePurchaseWithId:(NSString *)productId
                        userId:(NSString *)userId
               completionBlock:(IAPCompletionBlock)completion{
    [[IAPManager shared] completePurchaseWithId:productId
                                         userId:userId
                                completionBlock:(IAPCompletionBlock)completion];
}

#pragma mark - Private

- (void)showLoading{
    UIWindow *window = [self window];
    self.loadingView.frame = window.frame;
    [window addSubview:_loadingView];
    [_loadingView show];
}

- (void)dismissLoading{
    [_loadingView dismiss];
}

- (void)purchaseWithId:(NSString *)productId
                userId:(NSString *)userId
       completionBlock:(IAPCompletionBlock)completion{
    if (![SKPaymentQueue canMakePayments]){
        if (completion){
            completion(IAPResultCodeUserCanceled, @"用户禁止使用内购");
        }
        return;
    }
    self.completionBlock = completion;
    self.productId = productId;
    self.userId = userId;
    [self getProductInfo:productId];
}

- (void)checkIfLocalReceiptsNotValided:(IAPCompletionBlock)completion{
    NSFileManager *fileManager = [[NSFileManager alloc] init];
    [self.ioQueue addOperationWithBlock:^{
        NSArray *files = [self filesAtPath:[self filePathBase] fileManager:fileManager];
        NSMutableArray *results = [NSMutableArray arrayWithCapacity:files.count];
        for (NSString *item in files) {
            [results addObject:[self dataWithFile:item]];
        }
        if (completion) {
            completion(IAPResultCodeSuccess, results);
        }
    }];
}

- (void)completePurchaseWithId:(NSString *)productId
                        userId:(NSString *)userId
               completionBlock:(IAPCompletionBlock)completion{
    NSFileManager *fileManager = [[NSFileManager alloc] init];
    [self.ioQueue addOperationWithBlock:^{
        NSString *fileName = [NSString stringWithFormat:@"%@+%@", productId, userId];
        NSString *encodeFileName = [IAPTools encodeString:fileName];
        NSString *filePath = [self.filePathBase stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@", encodeFileName, kFileExt]];
        BOOL success = [self deleteFileWith:filePath fileManager:fileManager];
        if (completion) {
            completion(success ? IAPResultCodeSuccess : IAPResultCodeFailed, nil);
        }
    }];
}

- (void)getProductInfo:(NSString *)productIdentifier {
    [self showLoading];
    
    NSArray *product = [[NSArray alloc] initWithObjects: productIdentifier, nil];
    NSSet *set = [NSSet setWithArray: product];
    SKProductsRequest * request = [[SKProductsRequest alloc] initWithProductIdentifiers: set];
    request.delegate = self;
    [request start];
}

#pragma mark - SKProductsRequestDelegate

- (void)productsRequest:(SKProductsRequest *)request didReceiveResponse:(SKProductsResponse *)response{
    
    [self dismissLoading];
    if (response.products.count == 0){
        return;// 获取不到内购产品
    }
    
    SKProduct *product = [response.products firstObject];
    UIViewController *rootViewController = [[[UIApplication sharedApplication] keyWindow] rootViewController];
    [rootViewController showAlertWithTitle:[NSString stringWithFormat:@"购买%@, 价格: %@元", product.localizedTitle, [product.price descriptionWithLocale:product.priceLocale]]
                                   message:product.localizedDescription
                            preferredStyle:UIAlertControllerStyleAlert
                            responseHandle:^(NSInteger index) {
                                if (index == 1){
                                    SKPayment * payment = [SKPayment paymentWithProduct:product];
                                    [[SKPaymentQueue defaultQueue] addPayment:payment];
                                }else if (index == 0){
                                    if (self.completionBlock){
                                        self.completionBlock(IAPResultCodeUserCanceled, @"用户取消支付");
                                    }
                                }
                            }
                        cancelActionAtLast:true buttonTitles:@"确定", nil];
}


#pragma mark - SKPaymentTransactionObserver

- (void)paymentQueue:(SKPaymentQueue *)queue updatedTransactions:(NSArray *)transactions {
    [self showLoading];
    for (SKPaymentTransaction *transaction in transactions)
    {
        switch (transaction.transactionState)
        {
            case SKPaymentTransactionStatePurchased://交易完成
                // 验证
                self.receipt = [NSData dataWithContentsOfURL:[[NSBundle mainBundle] appStoreReceiptURL]];
                if (!self.receipt){
                    if (self.completionBlock){
                        [self dismissLoading];
                        self.completionBlock(IAPResultCodeFailed, @"找不到购买凭证!");
                    }
                    return;
                }
                if (self.completionBlock){
                    [self dismissLoading];
                    self.completionBlock(IAPResultCodeValidingWithServer, @"正在与服务器验证购买凭证...");
                }
                [self completeTransaction:transaction];
                [self storeReceipt:self.receipt productId:self.productId userId:self.userId];
                break;
            case SKPaymentTransactionStateFailed://交易失败
                [self dismissLoading];
                [self failedTransaction:transaction];
                break;
            case SKPaymentTransactionStateRestored://已经购买过该商品
                [self restoreTransaction:transaction];
                break;
            default:
                break;
        }
    }
}

- (void)completeTransaction:(SKPaymentTransaction *)transaction {
    [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
}

- (void)failedTransaction:(SKPaymentTransaction *)transaction {
    
    if(transaction.error.code != SKErrorPaymentCancelled) {
        UIViewController *rootViewController = [[[UIApplication sharedApplication] keyWindow] rootViewController];
        [rootViewController showAlertWithTitle:@"购买失败"
                                       message:@"是否重试?"
                                preferredStyle:UIAlertControllerStyleAlert
                                responseHandle:^(NSInteger index) {
                                    if (index == 1){
                                        [self getProductInfo:self.productId];
                                    }else{
                                        if (self.completionBlock){
                                            [self dismissLoading];
                                            NSString *desc = [NSString stringWithFormat:@"购买失败: %@", transaction.error.localizedDescription];
                                            self.completionBlock(IAPResultCodeFailed, desc);
                                        }
                                    }
                                } cancelActionAtLast:true buttonTitles:@"重试", nil];
    } else {
        [self dismissLoading];
        // 用户取消购买
        if (self.completionBlock){
            self.completionBlock(IAPResultCodeUserCanceled, @"用户取消购买");
        }
    }
    
    [[SKPaymentQueue defaultQueue] finishTransaction: transaction];
}

- (void)restoreTransaction:(SKPaymentTransaction *)transaction {
    [[SKPaymentQueue defaultQueue] finishTransaction: transaction];
}

#pragma mark - IO Operations

- (void)storeReceipt:(NSData *)receipt productId:(NSString *)productId userId:(NSString *)userId{
    [self.ioQueue addOperationWithBlock:^{
        NSString *fileName = [NSString stringWithFormat:@"%@+%@", productId, userId];
        NSString *encodeFileName = [IAPTools encodeString:fileName];
        NSString *filePath = [self.filePathBase stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@", encodeFileName, kFileExt]];
        [receipt writeToFile:filePath atomically:true];
    }];
}

- (NSArray <NSString *>*)filesAtPath:(NSString *)basePath fileManager:(NSFileManager *)fileManager{
    if ([fileManager fileExistsAtPath:basePath]) {
        NSMutableArray *temp = [NSMutableArray array];
        NSArray *childerFiles = [fileManager subpathsAtPath:basePath];
        for (NSString *fileName in childerFiles) {
            NSString *fileExt = [[fileName componentsSeparatedByString:@"."] lastObject];
            if ([fileExt isEqualToString:kFileExt]){
                NSString *absolutePath = [basePath stringByAppendingPathComponent:fileName];
                [temp addObject:absolutePath];
            }
        }
        return temp;
    }
    return nil;
}

- (NSDictionary *)dataWithFile:(NSString *)filePath{
    if (filePath) {
        NSData *receiptData = [NSData dataWithContentsOfFile:filePath];
        NSString *lastPathComponent = filePath.lastPathComponent;
        NSString *fileName = [[lastPathComponent componentsSeparatedByString:@"."] firstObject];
        NSString *decodeString = [IAPTools decodeString:fileName];
        NSArray *names = [decodeString componentsSeparatedByString:@"+"];
        NSDictionary *result = @{
                                 @"productId":[names firstObject],
                                 @"userId":[names lastObject],
                                 @"receiptData": receiptData
                                 };
        return result;
    }
    return nil;
}

- (BOOL)deleteFileWith:(NSString *)path fileManager:(NSFileManager *)fileManager{
    NSError *error = nil;
    [fileManager removeItemAtPath:path error:&error];
    if (error) {
        NSLog(@"*******删除文件失败********");
        return false;
    }
    return true;
}

#pragma mark - Testing 

+ (void)validReceiptWithAppStore:(IAPCompletionBlock)completion{ // 仅供沙箱测试使用
    NSData *receipt = [[IAPManager shared] receipt];
    NSError *error = nil;
    NSDictionary *requestContents = @{
                                      @"receipt-data": [receipt base64EncodedStringWithOptions:0]
                                      };
    NSData *requestData = [NSJSONSerialization dataWithJSONObject:requestContents
                                                          options:0
                                                            error:&error];
    
    if (!requestData) {
        if (completion){
            completion(IAPResultCodeFailed, @"找不到Receipt");
            return;
        }
    }
    // https://buy.itunes.apple.com/verifyReceipt 正式地址
    NSURL *storeURL = [NSURL URLWithString:@"https://sandbox.itunes.apple.com/verifyReceipt"];
    NSMutableURLRequest *storeRequest = [NSMutableURLRequest requestWithURL:storeURL];
    [storeRequest setHTTPMethod:@"POST"];
    [storeRequest setHTTPBody:requestData];
    
    NSOperationQueue *queue = [[NSOperationQueue alloc] init];
    [NSURLConnection sendAsynchronousRequest:storeRequest queue:queue
                           completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError) {
                               if (connectionError) {
                                   if (completion){
                                       completion(IAPResultCodeFailed, @"验证时候网络出错");
                                   }
                               } else {
                                   NSError *error;
                                   NSDictionary *jsonResponse = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
                                   if (!jsonResponse) {
                                       if (completion){
                                           completion(IAPResultCodeFailed, @"验证返回数据有误");
                                       }
                                   }else{
                                       IAPResultCode code;
                                       NSString *hint;
                                       if ([[jsonResponse objectForKey:@"status"] integerValue]== 0){// 成功
                                           code = IAPResultCodeSuccess;
                                       }else{
                                           code = IAPResultCodeFailed;
                                           hint = [NSString stringWithFormat:@"ErrorCode: %@", [jsonResponse objectForKey:@"status"]];
                                           // 请参考 https://developer.apple.com/library/content/releasenotes/General/ValidateAppStoreReceipt/Chapters/ValidateRemotely.html#//apple_ref/doc/uid/TP40010573-CH104-SW1
                                       }
                                       if (completion){
                                           completion(code, hint);
                                       }
                                   }
                               }
                           }];
}


@end
