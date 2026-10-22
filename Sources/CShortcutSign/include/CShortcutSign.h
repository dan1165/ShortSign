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

/// Extracts the workflow plist from a signed AEA1 shortcut. Returns 0 on
/// success and a malloc'd buffer in `out` (free with shorts_free).
int shorts_extract(const void *signedShortcut, size_t signedShortcutSize,
                   void **out, size_t *outSize);

/// Generates a fresh P-256 root/leaf identity. Returns the raw X9.63 leaf key,
/// the leaf certificate (DER) and the root certificate (DER).
int shorts_create_identity(
    void **key, size_t *keySize,
    void **leafCert, size_t *leafSize,
    void **rootCert, size_t *rootSize);

/// Reads a certificate's validity dates as Unix timestamps.
int shorts_certificate_dates(
    const void *der, size_t derSize,
    long long *notBefore, long long *notAfter);

void shorts_free(void *pointer);

#endif
