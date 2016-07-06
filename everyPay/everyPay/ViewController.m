//
//  ViewController.m
//  everyPay
//
//  Created by Lauri Eskor on 24/08/15.
//  Copyright (c) 2015 MobiLab. All rights reserved.
//

#import "ViewController.h"
#import "EPApi.h"
#import "Constants.h"
#import "EPSession.h"

#import "NSDate+Additions.h"

@interface ViewController ()

@property (weak, nonatomic) IBOutlet UITextView *textView;
@property (nonatomic, copy) NSString *apiVersion;
@property (nonatomic, copy) NSDictionary *merchantInfo;
@property (nonatomic, strong) NSArray *accountIdChoices;
@property (nonatomic, strong) NSDictionary *baseUrlsChoices;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setApiVersion:@"2"];
    [self setAccountIdChoices:[NSArray arrayWithObjects:@"EUR3D1", @"EUR1", nil]];
    /*
     Dictionary structure:
     key -> [merchantApiBaseUrl, EveryPayApiBaseUrl, EveryPayApiHost]
     */
    NSArray *stagingArray = @[kMercantApiStaging, kEveryPayApiStaging, kEveryPayApiStagingHost];
    NSArray *demoArray = @[kMerchantApiDemo, kEveryPayApiDemo, kEveryPayApiDemoHost];
    NSMutableDictionary *baseUrlsDictionary = [NSMutableDictionary new];

    [baseUrlsDictionary setObject:stagingArray forKey:@"Staging environment"];
    [baseUrlsDictionary setObject:demoArray forKey:@"Demo environment"];
    [self setBaseUrlsChoices:[baseUrlsDictionary copy]];
}


- (void)getMerchantInfoWithCard:(EPCard *)card accountId:(NSString *)accountId {
    [self appendProgressLog:@"Get API credentials from merchant..."];
    [EPMerchantApi getMerchantDataWithSuccess:^(NSDictionary *dictionary) {
        [self appendProgressLog:@"Done"];
        [self setMerchantInfo:dictionary];
        [self sendCardCredentialsToEPWithMerchantInfo:dictionary andCard:card];
    } andError:^(NSError *error) {
        [self showAlertWithError:error];
    } apiVersion:self.apiVersion accountId:accountId];
}

- (void)sendCardCredentialsToEPWithMerchantInfo:(NSDictionary *)merchantInfo andCard:(EPCard *)card {
    [self appendProgressLog:@"Save card details with EvertPay API..."];
    [EPApi sendCard:card withMerchantInfo:merchantInfo withSuccess:^(NSDictionary *responseDictionary) {
        NSString *paymentState = [responseDictionary objectForKey:kPaymentState];
        if([paymentState isEqualToString:kAuthorised] || !paymentState){
            NSString *token = [responseDictionary objectForKey:kKeyEncryptedToken];
            [self appendProgressLog:@"Done"];
            [self payWithToken:token andMerchantInfo:merchantInfo];
        } else if ([paymentState isEqualToString:kPaymentStateWaiting3DsResponse]) {
            [self appendProgressLog:@"Done"];
            NSString *paymentReference = [responseDictionary objectForKey:kKeyPaymentReference];
            NSString *secureCodeOne = [responseDictionary objectForKey:kKeySecureCodeOne];
            NSString *hmac = [merchantInfo objectForKey:kKeyHmac];
            [self appendProgressLog:@"Starting 3DS authentication..."];
            [self startWebViewWithPaymentReference:paymentReference secureCodeOne:secureCodeOne hmac:hmac];
        }
    } andError:^(NSArray *errors) {
        [self showAlertWithError:[errors firstObject]];
    }];
}

- (void)payWithToken:(NSString *)token andMerchantInfo:(NSDictionary *)merchantInfo {
    [self appendProgressLog:@"Send card token to merchant server..."];

    [EPMerchantApi sendPaymentWithToken:token andMerchantInfo:merchantInfo withSuccess:^(NSDictionary *dictionary) {
        [self appendProgressLog:@"All done"];
    } andError:^(NSError *error) {
        [self showAlertWithError:error];
    }];
}

- (void)startWebViewWithPaymentReference:(NSString *)paymentReference secureCodeOne:(NSString *)secureCodeOne hmac:(NSString *)hmac {
    EPAuthenticationWebViewController *authenticationWebView = [[EPAuthenticationWebViewController alloc] initWithNibName:NSStringFromClass([EPAuthenticationWebViewController class]) bundle:nil];
    [authenticationWebView setDelegate:self];
    [authenticationWebView addURLParametersWithPaymentReference:paymentReference secureCodeOne:secureCodeOne hmac:hmac];
    [self.navigationController pushViewController:authenticationWebView animated:YES];
}
- (void)showAlertWithError:(NSError *)error {
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Note" message:error.localizedDescription delegate:nil cancelButtonTitle:@"Close" otherButtonTitles:nil];
    [alert show];
    [self appendProgressLog:@"Failed"];
}

- (void)appendProgressLog:(NSString *)log {
    NSString *stringToAppend = [NSString stringWithFormat:@"\n%@", log];
    [self.textView setText:[self.textView.text stringByAppendingString:stringToAppend]];
}

#pragma mark - CardInfoViewControllerDelegate
- (void)cardInfoViewController:(UIViewController *)controller didEnterInfoForCard:(EPCard *)card {
    [self.navigationController popToViewController:self animated:YES];
    [self showChooseApiBaseUrlActionSheetWithCard:card];
    
}

- (IBAction)restartTapped:(id)sender {
    [self.textView setText:@""];
    EPCardInfoViewController *cardInfoViewController = [[EPCardInfoViewController alloc] initWithNibName:NSStringFromClass([EPCardInfoViewController class]) bundle:nil];
    [cardInfoViewController setDelegate:self];
    [self.navigationController pushViewController:cardInfoViewController animated:YES];
    cardInfoViewController.edgesForExtendedLayout = UIRectEdgeNone;
    [self appendProgressLog:@"\n"];
}

- (void)authenticationCanceled {
    [self showAlertWithError:[NSError errorWithDomain:@"3Ds authentication canceled" code:1000 userInfo:nil]];
}
- (void)authenticationFailedWithErrorCode:(NSInteger)errorCode {
    [self.navigationController popToViewController:self animated:YES];
    NSLog(@"payment Failed with code %ld", (long)errorCode);
    [self showAlertWithError:[NSError errorWithDomain:@"3Ds authentication failed" code:errorCode userInfo:nil]];
}

- (void)authenticationSucceededWithPayentReference:(NSString *)paymentReference hmac:(NSString *)hmac {
    [self.navigationController popToViewController:self animated:YES];
    NSLog(@"payment succeeded with reference %@", paymentReference);
    [self appendProgressLog:@"Done"];
    [self appendProgressLog:@"Confirming 3DS with Everypay server ...."];
    [EPApi encryptedPaymentInstrumentsConfirmedWithPaymentReference:paymentReference hmac:hmac apiVersion:_apiVersion withSuccess:^(NSDictionary *dictionary) {
        NSString *token = [dictionary objectForKey:kKeyEncryptedToken];
        [self appendProgressLog:@"Done"];
        [self payWithToken:token andMerchantInfo:_merchantInfo];
    } andError:^(NSArray *array) {
        [self showAlertWithError:array[0]];
    }];
}

- (void)showChooseAccountActionSheetWithCard:(EPCard *)card{
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *actionSheet = [UIAlertController alertControllerWithTitle:@"Choose account" message:@"Choose accountID for non-3Ds or 3Ds flow" preferredStyle:UIAlertControllerStyleActionSheet];
        if ([self.accountIdChoices count] == 0) {
            [self showResultAlertWithTitle:@"No accounts" message:@"You haven't provided any accounts"];
            return;
        }
        for (NSString *accountID in self.accountIdChoices) {
            [actionSheet addAction:[UIAlertAction actionWithTitle:accountID style:UIAlertActionStyleDefault handler:^(UIAlertAction *_Nonnull action) {
                [self getMerchantInfoWithCard:card accountId:accountID];
            }]];
        }
        [actionSheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:actionSheet animated:YES completion:nil];
    });
}
- (void)showChooseApiBaseUrlActionSheetWithCard:(EPCard *)card{
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *actionSheet = [UIAlertController alertControllerWithTitle:@"Choose environment" message:@"Choose environment for requests" preferredStyle:UIAlertControllerStyleActionSheet];
        if ([self.baseUrlsChoices count] == 0) {
            [self showResultAlertWithTitle:@"No base URLs" message:@"You haven't provided any base URLs"];
            return;
        }
        for (NSString *environment in [self.baseUrlsChoices allKeys]) {
            [actionSheet addAction:[UIAlertAction actionWithTitle:environment style:UIAlertActionStyleDefault handler:^(UIAlertAction *_Nonnull action) {
                NSArray *values = [self.baseUrlsChoices objectForKey:environment];
                [[EPSession sharedInstance] setEverypayApiHost:[values objectAtIndex:2]];
                [[EPSession sharedInstance] setEveryPayApiBaseUrl:[values objectAtIndex:1]];
                [[EPSession sharedInstance] setMerchantApiBaseUrl:[values objectAtIndex:0]];
                [self showChooseAccountActionSheetWithCard:card];
            }]];
        }
        [actionSheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:actionSheet animated:YES completion:nil];
    });
}

- (void)showResultAlertWithTitle:(NSString *)title message:(NSString *)message {
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alertController = [UIAlertController alertControllerWithTitle:title
                                                                                 message:message
                                                                          preferredStyle:UIAlertControllerStyleAlert];
        [alertController addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [weakSelf presentViewController:alertController animated:YES completion:nil];
    });
}
- (void)closeWebViewController{
    [self.navigationController popToViewController:self animated:YES];
}

@end
