//
//  Jailbreaker.m
//  Dopamine
//
//  Created by Lars Fröder on 10.01.24.
//

#import "Jailbreaker.h"
#import "EnvironmentManager.h"
#import "ExploitManager.h"
#import <sys/stat.h>
#import "Util.h"
#import <compression.h>
#import <xpf/xpf.h>
#include <dlfcn.h>

NSString *const JBErrorDomain = @"JBErrorDomain";
typedef NS_ENUM(NSInteger, JBErrorCode) {
    JBErrorCodeFailedToFindKernel            = -1,
    JBErrorCodeFailedKernelPatchfinding      = -2,
    JBErrorCodeFailedLoadingExploit          = -3,
    JBErrorCodeFailedExploitation            = -4,
};

#include <libjailbreak/primitives_external.h>
#include <libjailbreak/primitives.h>
#include <libjailbreak/primitives_IOSurface.h>
#include <libjailbreak/translation.h>
#include <libjailbreak/info.h>

@implementation Jailbreaker

- (NSError *)gatherSystemInformation
{
    NSString *kernelPath = [[EnvironmentManager sharedManager] accessibleKernelPath];
    if (!kernelPath) return [NSError errorWithDomain:JBErrorDomain code:JBErrorCodeFailedToFindKernel userInfo:@{NSLocalizedDescriptionKey:@"Failed to find kernelcache"}];
    printf("Kernel at %s\n", kernelPath.UTF8String);
    
    xpf_start_with_kernel_path(kernelPath.fileSystemRepresentation);
    
    const char *sets[] = {
        "translation",
        "trustcache",
        "physmap",
        "struct",
        "physrw",
        "perfkrw",
        "badRecovery",
        NULL
    };
    
    if (!xpf_set_is_supported("badRecovery")) {
        sets[6] = NULL;
    }

    _systemInfoXdict = xpf_construct_offset_dictionary(sets);
    if (_systemInfoXdict) {
        printf("System Info:\n");
        xpc_dictionary_apply(_systemInfoXdict, ^bool(const char *key, xpc_object_t value) {
            if (xpc_get_type(value) == XPC_TYPE_UINT64) {
                printf("0x%016llx <- %s\n", xpc_uint64_get_value(value), key);
            }
            return true;
        });
    }
    if (!_systemInfoXdict) {
        return [NSError errorWithDomain:JBErrorDomain code:JBErrorCodeFailedKernelPatchfinding userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"XPF failed with error: (%s)", xpf_get_error()]}];
    }
    xpf_stop();
    
    jbinfo_initialize_dynamic_offsets(_systemInfoXdict);
    jbinfo_initialize_hardcoded_offsets();
    _systemInfoXdict = jbinfo_get_serialized();
    
    if (_systemInfoXdict) {
        printf("System Info libjailbreak:\n");
        xpc_dictionary_apply(_systemInfoXdict, ^bool(const char *key, xpc_object_t value) {
            if (xpc_get_type(value) == XPC_TYPE_UINT64) {
                if (xpc_uint64_get_value(value)) {
                    printf("0x%016llx <- %s\n", xpc_uint64_get_value(value), key);
                }
            }
            return true;
        });
    }
    
    return nil;
}

- (NSError *)doExploitation
{
    Exploit *kernelExploit = [ExploitManager sharedManager].preferredKernelExploit;
    printf("Picked Kernel Exploit: %s\n", kernelExploit.description.UTF8String);
    
    if ([kernelExploit load] != 0) return [NSError errorWithDomain:JBErrorDomain code:JBErrorCodeFailedLoadingExploit userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"Failed to load kernel exploit: %s", dlerror()]}];
    if ([kernelExploit run] != 0) return [NSError errorWithDomain:JBErrorDomain code:JBErrorCodeFailedExploitation userInfo:@{NSLocalizedDescriptionKey:@"Failed to exploit kernel"}];
    
    jbinfo_initialize_boot_constants();
    libjailbreak_translation_primitives_init();
    libjailbreak_IOSurface_primitives_init();
    
    printf("We out here! (%x)\n", kread32(kconstant(base)));
    
    [kernelExploit cleanup];
    return nil;
}


- (NSError *)run
{
    NSError *err = nil;
    err = [self gatherSystemInformation];
    if (err) return err;
    err = [self doExploitation];
    if (err) return err;
    
    return nil;
}

@end
