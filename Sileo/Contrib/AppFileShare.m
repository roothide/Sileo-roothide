//
//  AppFileShare.m
//  Sileo
//
//  Created by admin on 7/5/2024.
//  Copyright © 2024 Sileo Team. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface LSApplicationProxy : NSObject
- (id)correspondingApplicationRecord;
+ (id)applicationProxyForIdentifier:(id)arg1;
- (id)localizedNameForContext:(id)arg1;
- (NSURL *)bundleURL;
- (NSURL *)containerURL;
- (NSURL *)dataContainerURL;
- (NSString *)bundleExecutable;
- (NSString *)bundleIdentifier;
- (NSString *)vendorName;
- (NSString *)teamID;
- (NSString *)applicationType;
- (NSSet *)claimedURLSchemes;
- (BOOL)isDeletable;
- (NSDictionary*)environmentVariables;
@property (nonatomic,readonly) NSString * applicationIdentifier;
@property (nonatomic,readonly) NSDictionary *groupContainerURLs;
@end


@interface LSApplicationWorkspace : NSObject
+ (id)defaultWorkspace;
-(id)operationToOpenResource:(id)arg1 usingApplication:(id)arg2 userInfo:(id)arg3;
@end

BOOL IsAppAvailable(NSString* bundleId)
{
    LSApplicationProxy *app = [LSApplicationProxy applicationProxyForIdentifier:bundleId];
    return app && app.bundleExecutable;
}

BOOL ShareFileToApp(NSString* bundleId, NSString* filePath)
{
    LSApplicationProxy *app = [LSApplicationProxy applicationProxyForIdentifier:bundleId];
    if(!app || !app.bundleExecutable) return NO;
    
    NSOperation *op = [[LSApplicationWorkspace defaultWorkspace]
                           operationToOpenResource:[NSURL fileURLWithPath:filePath]
                           usingApplication:[app applicationIdentifier] userInfo:nil];
    
    if(!op) return NO;

    [op start];
    
    NSLog(@"SileoLog: ShareFileToApp %@ %d/%d/%d/%d %@", [app applicationIdentifier], [op isExecuting], [op isFinished], [op isConcurrent], [op isCancelled], filePath);
    
    return YES;
}
