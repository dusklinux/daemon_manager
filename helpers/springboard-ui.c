// A rootless SpringBoard-only companion. Read settings once per respring;
// install hooks only for disabled interfaces. No timer or resident helper process.
typedef void *Object;
typedef void *Class;
typedef void *Method;
typedef void *Selector;
typedef void (*Implementation)(void);
#if __has_include(<stdio.h>)
#include <stdio.h>
typedef FILE File;
#else
// Local device tests can be cross-built without an SDK. Release builds
// use Xcode's iPhoneOS SDK and the standard declarations above.
typedef void File;
extern File *fopen(const char *, const char *);
extern int fprintf(File *, const char *, ...);
extern int fclose(File *);
#endif
extern Class objc_getClass(const char *);
extern Selector sel_registerName(const char *);
extern Method class_getInstanceMethod(Class, Selector);
extern const char *method_getTypeEncoding(Method);
extern void objc_msgSend(void);
extern void *objc_autoreleasePoolPush(void);
extern void objc_autoreleasePoolPop(void *);
extern Object NSHomeDirectory(void);
extern void *dlopen(const char *, int);
extern void *dlsym(void *, const char *);
extern int strcmp(const char *, const char *);
extern int getpid(void);

typedef void (*HookMessage)(Class, Selector, Implementation, Implementation *);
static HookMessage hookMessage;
static void (*dockLayout)(Object, Selector);
static void (*modernStatusLayout)(Object, Selector);
static void (*legacyStatusLayout)(Object, Selector);

static Object string(const char *value) {
    return ((Object (*)(Class, Selector, const char *))objc_msgSend)(
        objc_getClass("NSString"), sel_registerName("stringWithUTF8String:"), value);
}

static Object childPath(Object home, const char *relative) {
    return ((Object (*)(Object, Selector, Object))objc_msgSend)(
        home, sel_registerName("stringByAppendingPathComponent:"), string(relative));
}

static _Bool compatible(const char *name, const char *selector, const char *encoding) {
    Class cls = objc_getClass(name);
    Method method = cls ? class_getInstanceMethod(cls, sel_registerName(selector)) : 0;
    return method && strcmp(method_getTypeEncoding(method), encoding) == 0;
}

static void hook(const char *name, const char *selector, Implementation replacement,
                 Implementation *original) {
    hookMessage(objc_getClass(name), sel_registerName(selector), replacement, original);
}

static _Bool denied(Object self, Selector cmd) { return 0; }
static void noPresentation(Object self, Selector cmd, _Bool animated) {}
static void hide(Object view) {
    ((void (*)(Object, Selector, _Bool))objc_msgSend)(view, sel_registerName("setHidden:"), 1);
}
static void hiddenDockLayout(Object self, Selector cmd) { dockLayout(self, cmd); hide(self); }
static void hiddenModernStatusLayout(Object self, Selector cmd) { modernStatusLayout(self, cmd); hide(self); }
static void hiddenLegacyStatusLayout(Object self, Selector cmd) { legacyStatusLayout(self, cmd); hide(self); }

__attribute__((constructor)) static void configure(void) {
    void *pool = objc_autoreleasePoolPush();
    Object home = NSHomeDirectory();
    Object path = childPath(home, "Library/Preferences/com.dusklinux.DaemonManagerUI.plist");
    Object settings = ((Object (*)(Class, Selector, Object))objc_msgSend)(
        objc_getClass("NSDictionary"), sel_registerName("dictionaryWithContentsOfFile:"), path);
    const char *keys[] = {"controlCenter", "appLibrary", "dock", "statusBar"};
    _Bool requested[4] = {0};
    for (unsigned i = 0; i < 4; i++) {
        Object value = ((Object (*)(Object, Selector, Object))objc_msgSend)(
            settings, sel_registerName("objectForKey:"), string(keys[i]));
        requested[i] = value && (( _Bool (*)(Object, Selector))objc_msgSend)(value, sel_registerName("boolValue"));
    }
    // ElleKit's documented Substrate compatibility entry point on this bootstrap.
    void *library = dlopen("/var/jb/usr/lib/libsubstrate.dylib", 1);
    hookMessage = library ? (HookMessage)dlsym(library, "MSHookMessageEx") : 0;
    _Bool modern = compatible("_UIStatusBar", "layoutSubviews", "v16@0:8");
    _Bool legacy = compatible("UIStatusBar", "layoutSubviews", "v16@0:8");
    _Bool supported[4] = {
        compatible("SBControlCenterController", "canBePresented", "B16@0:8") &&
        compatible("SBControlCenterController", "allowShowTransitionSystemGesture", "B16@0:8") &&
        compatible("SBControlCenterController", "presentAnimated:", "v20@0:8B16"),
        compatible("SBIconController", "isAppLibraryAllowed", "B16@0:8") &&
        compatible("SBIconController", "isAppLibrarySupported", "B16@0:8"),
        compatible("SBDockView", "layoutSubviews", "v16@0:8"),
        modern || legacy
    };
    _Bool active[4] = {0};
    for (unsigned i = 0; i < 4; i++) {
        supported[i] = supported[i] && hookMessage;
        active[i] = supported[i] && requested[i];
    }
    if (active[0]) {
        hook("SBControlCenterController", "canBePresented", (Implementation)denied, 0);
        hook("SBControlCenterController", "allowShowTransitionSystemGesture", (Implementation)denied, 0);
        hook("SBControlCenterController", "presentAnimated:", (Implementation)noPresentation, 0);
    }
    if (active[1]) {
        hook("SBIconController", "isAppLibraryAllowed", (Implementation)denied, 0);
        hook("SBIconController", "isAppLibrarySupported", (Implementation)denied, 0);
    }
    if (active[2]) hook("SBDockView", "layoutSubviews", (Implementation)hiddenDockLayout, (Implementation *)&dockLayout);
    if (active[3]) {
        if (modern) hook("_UIStatusBar", "layoutSubviews", (Implementation)hiddenModernStatusLayout, (Implementation *)&modernStatusLayout);
        if (legacy) hook("UIStatusBar", "layoutSubviews", (Implementation)hiddenLegacyStatusLayout, (Implementation *)&legacyStatusLayout);
    }
    Object reportPath = childPath(home, "Library/Caches/daemon-manager-ui-runtime.json");
    const char *reportCString = ((const char *(*)(Object, Selector))objc_msgSend)(reportPath, sel_registerName("UTF8String"));
    File *file = fopen(reportCString, "w");
    if (file) {
        fprintf(file, "{\"pid\":%d,\"version\":1,\"supported\":{", getpid());
        for (unsigned i = 0; i < 4; i++) fprintf(file, "%s\"%s\":%s", i ? "," : "", keys[i], supported[i] ? "true" : "false");
        fprintf(file, "},\"disabled\":{");
        for (unsigned i = 0; i < 4; i++) fprintf(file, "%s\"%s\":%s", i ? "," : "", keys[i], active[i] ? "true" : "false");
        fprintf(file, "}}\n");
        fclose(file);
    }
    objc_autoreleasePoolPop(pool);
}
