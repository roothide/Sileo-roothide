#import <Foundation/Foundation.h>
#import <TargetConditionals.h>

#import "roothide.h"

#if TARGET_OS_SIMULATOR || TARGET_OS_MACCATALYST

static const char *RootHidePassthroughPath(const char *path) {
    static thread_local std::string cachedPath;
    cachedPath = path ? path : "";
    return cachedPath.c_str();
}

const char *rootfs_alloc(const char *path) {
    return strdup(path ? path : "");
}

const char *jbroot_alloc(const char *path) {
    return strdup(path ? path : "");
}

const char *jbrootat_alloc(int fd, const char *path) {
    (void)fd;
    return strdup(path ? path : "");
}

unsigned long long jbrand() {
    return 0;
}

const char *jbroot(const char *path) {
    return RootHidePassthroughPath(path);
}

const char *rootfs(const char *path) {
    return RootHidePassthroughPath(path);
}

NSString * __attribute__((overloadable)) jbroot(NSString *path) {
    return path ?: @"";
}

NSString * __attribute__((overloadable)) rootfs(NSString *path) {
    return path ?: @"";
}

std::string jbroot(std::string path) {
    return path;
}

std::string rootfs(std::string path) {
    return path;
}

#endif
