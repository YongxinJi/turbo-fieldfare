#include <limits.h>
#include <mach-o/dyld.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int main(int argc, char *argv[]) {
    char unresolved[PATH_MAX];
    uint32_t size = sizeof(unresolved);
    if (_NSGetExecutablePath(unresolved, &size) != 0) {
        fputs("TurboFieldfare launcher path is too long\n", stderr);
        return 1;
    }

    char resolved[PATH_MAX];
    if (realpath(unresolved, resolved) == NULL) {
        perror("TurboFieldfare launcher");
        return 1;
    }

    char *separator = strrchr(resolved, '/');
    if (separator == NULL) {
        fputs("TurboFieldfare launcher path is invalid\n", stderr);
        return 1;
    }
    *separator = '\0';

    char helper[PATH_MAX];
    int length = snprintf(
        helper,
        sizeof(helper),
        "%s/../Helpers/TurboFieldfareMac",
        resolved);
    if (length < 0 || length >= (int)sizeof(helper)) {
        fputs("TurboFieldfare helper path is too long\n", stderr);
        return 1;
    }

    argv[0] = helper;
    execv(helper, argv);
    perror("TurboFieldfare launcher");
    return 1;
}
