//
//  MPVungleRouter.m
//  MoPubSDK
//
//  Copyright (c) 2015 MoPub. All rights reserved.
//

#import "MPVungleRouter.h"
#import "MPInstanceProvider+Vungle.h"
#import "MPLogging.h"
#import "VungleInstanceMediationSettings.h"
#import "MPRewardedVideoError.h"

static NSString *gAppId = nil;
static NSString *const kMPVungleRewardedAdCompletedView = @"completedView";
static NSString *const kMPVungleAdUserDidDownloadKey = @"didDownload";

@interface MPVungleRouter ()

@property (nonatomic, assign) BOOL isAdPlaying;
@property (nonatomic, assign) NSInteger checkAdTimeout;

@end

@implementation MPVungleRouter

+ (void)setAppId:(NSString *)appId
{
    gAppId = [appId copy];
}

+ (MPVungleRouter *)sharedRouter
{
    return [[MPInstanceProvider sharedProvider] sharedMPVungleRouter];
}

- (void)requestInterstitialAdWithCustomEventInfo:(NSDictionary *)info delegate:(id<MPVungleRouterDelegate>)delegate
{
    if (!self.isAdPlaying) {
        [self requestAdWithCustomEventInfo:info delegate:delegate];
    } else {
        [delegate vungleAdDidFailToLoad:nil];
    }
}

- (void)requestRewardedVideoAdWithCustomEventInfo:(NSDictionary *)info delegate:(id<MPVungleRouterDelegate>)delegate
{
    if (!self.isAdPlaying) {
        [self requestAdWithCustomEventInfo:info delegate:delegate];
    } else {
        NSError *error = [NSError errorWithDomain:MoPubRewardedVideoAdsSDKDomain code:MPRewardedVideoAdErrorUnknown userInfo:nil];
        [delegate vungleAdDidFailToLoad:error];
    }
}

- (void)requestAdWithCustomEventInfo:(NSDictionary *)info delegate:(id<MPVungleRouterDelegate>)delegate
{
    self.delegate = delegate;

    static dispatch_once_t vungleInitToken;
    dispatch_once(&vungleInitToken, ^{
        NSString *appId = [info objectForKey:@"appId"];
        if ([appId length] == 0) {
            appId = gAppId;
        }

        [[VungleSDK sharedSDK] startWithAppId:appId];
        [[VungleSDK sharedSDK] setDelegate:self];
    });

    // Use polling as a workaround because events do not reflect the real state.
    // We must return to the event-based model when it will be fixed.
    [self startCheckingAdStatus];

    // MoPub timeout will handle the case for an ad failing to load.
}

- (void)startCheckingAdStatus
{
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(checkAdStatus) object:nil];
	self.checkAdTimeout = 30;
	[self checkAdStatus];
}

- (void)checkAdStatus
{
	if ([[VungleSDK sharedSDK] isAdPlayable])
		[self.delegate vungleAdDidLoad];
	else if (self.checkAdTimeout > 0) {
		self.checkAdTimeout--;
		[self performSelector:@selector(checkAdStatus) withObject:nil afterDelay:1.0];
	}
}

- (BOOL)isAdAvailable
{
    return [[VungleSDK sharedSDK] isAdPlayable];
}

- (void)presentInterstitialAdFromViewController:(UIViewController *)viewController withDelegate:(id<MPVungleRouterDelegate>)delegate
{
    if (!self.isAdPlaying && self.isAdAvailable) {
        self.delegate = delegate;
        self.isAdPlaying = YES;

        BOOL success = [[VungleSDK sharedSDK] playAd:viewController error:nil];

        if (!success) {
            [delegate vungleAdDidFailToPlay:nil];
        }
    } else {
        [delegate vungleAdDidFailToPlay:nil];
    }
}

- (void)presentRewardedVideoAdFromViewController:(UIViewController *)viewController settings:(VungleInstanceMediationSettings *)settings delegate:(id<MPVungleRouterDelegate>)delegate
{
    if (!self.isAdPlaying && self.isAdAvailable) {
        self.delegate = delegate;
        self.isAdPlaying = YES;
        NSDictionary *options;
        if (settings && [settings.userIdentifier length]) {
            options = @{VunglePlayAdOptionKeyIncentivized : @(YES), VunglePlayAdOptionKeyUser : settings.userIdentifier};
        } else {
            options = @{VunglePlayAdOptionKeyIncentivized : @(YES)};
        }

        BOOL success = [[VungleSDK sharedSDK] playAd:viewController withOptions:options error:nil];

        if (!success) {
            [delegate vungleAdDidFailToPlay:nil];
        }
    } else {
        NSError *error = [NSError errorWithDomain:MoPubRewardedVideoAdsSDKDomain code:MPRewardedVideoAdErrorNoAdsAvailable userInfo:nil];
        [delegate vungleAdDidFailToPlay:error];
    }
}

- (void)clearDelegate:(id<MPVungleRouterDelegate>)delegate
{
    if(self.delegate == delegate)
    {
        [self setDelegate:nil];
    }
}

#pragma mark - private

- (void)vungleAdDidFinish
{
    [self.delegate vungleAdWillDisappear];
    self.isAdPlaying = NO;
}

#pragma mark - VungleSDKDelegate

- (void)vungleSDKwillShowAd
{
    [self.delegate vungleAdWillAppear];
}

- (void)vungleSDKwillCloseAdWithViewInfo:(NSDictionary *)viewInfo willPresentProductSheet:(BOOL)willPresentProductSheet
{
    if ([viewInfo[kMPVungleAdUserDidDownloadKey] isEqual:@YES]) {
        [self.delegate vungleAdWasTapped];
    }

    if ([[viewInfo objectForKey:kMPVungleRewardedAdCompletedView] boolValue] && [self.delegate respondsToSelector:@selector(vungleAdShouldRewardUser)]) {
        [self.delegate vungleAdShouldRewardUser];
    }

    if (!willPresentProductSheet) {
        [self vungleAdDidFinish];
    }
}

- (void)vungleSDKwillCloseProductSheet:(id)productSheet
{
    [self vungleAdDidFinish];
}

@end
