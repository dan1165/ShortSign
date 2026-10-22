#include "CShortcutSign.h"
#include "sign.h"
#include <stdlib.h>

int shorts_sign(
    const void *plist, size_t plistSize,
    const void *key, size_t keySize,
    const void *authData, size_t authDataSize,
    void **out, size_t *outSize)
{
    (void)keySize;
    uint8_t *signedShortcut = sign_shortcut_with_private_key_and_auth_data(
        (void *)plist, plistSize,
        (void *)key,
        (uint8_t *)authData, authDataSize,
        outSize);
    if (signedShortcut == NULL) {
        return -1;
    }
    *out = signedShortcut;
    return 0;
}

void shorts_free(void *pointer)
{
    free(pointer);
}
