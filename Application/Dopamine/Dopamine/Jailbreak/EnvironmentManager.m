//
//  EnvironmentManager.m
//  Dopamine
//
//  Created by Lars Fröder on 10.01.24.
//

#import "EnvironmentManager.h"

#import <sys/sysctl.h>
#import <libgrabkernel/libgrabkernel.h>

@implementation EnvironmentManager

+ (instancetype)sharedManager
{
    static EnvironmentManager *shared;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[EnvironmentManager alloc] init];
    });
    return shared;
}

- (BOOL)isArm64e
{
    cpu_subtype_t cpusubtype = 0;
    size_t len = sizeof(cpusubtype);
    if (sysctlbyname("hw.cpusubtype", &cpusubtype, &len, NULL, 0) == -1) { return NO; }
    return (cpusubtype & ~CPU_SUBTYPE_MASK) == CPU_SUBTYPE_ARM64E;

}

- (NSString *)versionSupportString
{
    if ([self isArm64e]) {
        return @"iOS 15.0 - 16.5.1 (arm64e)";
    }
    else {
        return @"iOS 15.0 - 16.6.1 (arm64)";
    }
}

- (BOOL)installedThroughTrollStore
{
    NSString* trollStoreMarkerPath = [[[NSBundle mainBundle].bundlePath stringByDeletingLastPathComponent] stringByAppendingString:@"_TrollStore"];
    return [[NSFileManager defaultManager] fileExistsAtPath:trollStoreMarkerPath];
}


- (NSString *)accessibleKernelPath
{
    if ([self installedThroughTrollStore]) {
        // TODO: Return kernel path in /private/preboot
        return nil;
    }
    else {
        NSString *kernelcachePath = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/kernelcache"];
        if (![[NSFileManager defaultManager] fileExistsAtPath:kernelcachePath]) {
            if (grabkernel((char *)kernelcachePath.fileSystemRepresentation, 0) != 0) return nil;
        }
        return kernelcachePath;
    }
}

- (BOOL)isPACBypassRequired
{
    if (![self isArm64e]) return NO;
    
    if (@available(iOS 15.2, *)) {
        return NO;
    }
    return YES;
}

- (BOOL)isPPLBypassRequired
{
    return [self isArm64e];
}

@end
