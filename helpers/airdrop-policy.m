#import <Foundation/Foundation.h>
#import <dlfcn.h>
#include <stdio.h>
#include <string.h>

@interface NSObject (DaemonAirDropPolicy)
+ (id)sharedConnection;
- (BOOL)isAirDropAllowed;
- (void)setBoolValue:(BOOL)value forSetting:(NSString *)setting;
@end

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc != 2 || (strcmp(argv[1], "read") && strcmp(argv[1], "on") && strcmp(argv[1], "off"))) {
            fprintf(stderr, "Expected read, on, or off\n");
            return 64;
        }
        void *framework = dlopen("/System/Library/PrivateFrameworks/ManagedConfiguration.framework/ManagedConfiguration", RTLD_NOW);
        Class cls = NSClassFromString(@"MCProfileConnection");
        NSString *__unsafe_unretained *setting = framework ? (NSString *__unsafe_unretained *)dlsym(framework, "MCFeatureAirDropAllowed") : NULL;
        if (!cls || !setting || !*setting || ![cls respondsToSelector:@selector(sharedConnection)]) {
            fprintf(stderr, "AirDrop policy API unavailable\n");
            return 1;
        }
        id connection = [cls sharedConnection];
        if (![connection respondsToSelector:@selector(isAirDropAllowed)] ||
            ![connection respondsToSelector:@selector(setBoolValue:forSetting:)]) {
            fprintf(stderr, "AirDrop policy methods unavailable\n");
            return 1;
        }
        if (strcmp(argv[1], "read")) {
            BOOL requested = !strcmp(argv[1], "on");
            [connection setBoolValue:requested forSetting:*setting];
            BOOL verified = NO;
            for (int attempt = 0; attempt < 50; attempt++) {
                if ([connection isAirDropAllowed] == requested) { verified = YES; break; }
                [NSThread sleepForTimeInterval:0.1];
            }
            if (!verified) {
                fprintf(stderr, "AirDrop policy did not match the requested state\n");
                return 1;
            }
        }
        printf("airdrop_allowed=%d\n", [connection isAirDropAllowed] ? 1 : 0);
        return 0;
    }
}
