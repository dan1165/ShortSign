#ifndef CShortcutSign_h
#define CShortcutSign_h

#include <stddef.h>

/// Signs an unsigned shortcut plist. Returns 0 on success and a malloc'd
/// buffer in `out` (free with shorts_free), or -1 on failure.
int shorts_sign(
    const void *plist, size_t plistSize,
    const void *key, size_t keySize,
    const void *authData, size_t authDataSize,
    void **out, size_t *outSize);

void shorts_free(void *pointer);

#endif
