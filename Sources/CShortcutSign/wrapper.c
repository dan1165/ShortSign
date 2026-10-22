#include "CShortcutSign.h"
#include "extract.h"
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

int shorts_extract(const void *signedShortcut, size_t signedShortcutSize,
                   void **out, size_t *outSize)
{
    uint8_t *plist = extract_signed_shortcut_buffer(
        (uint8_t *)signedShortcut, signedShortcutSize, outSize);
    if (plist == NULL) {
        return -1;
    }
    *out = plist;
    return 0;
}

void shorts_free(void *pointer)
{
    free(pointer);
}
