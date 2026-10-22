#include "CShortcutSign.h"
#include <openssl/asn1.h>
#include <openssl/bn.h>
#include <openssl/core_names.h>
#include <openssl/evp.h>
#include <openssl/obj_mac.h>
#include <openssl/objects.h>
#include <openssl/rand.h>
#include <openssl/x509.h>
#include <openssl/x509v3.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static EVP_PKEY *generate_key(void) {
    EVP_PKEY_CTX *ctx = EVP_PKEY_CTX_new_from_name(NULL, "EC", NULL);
    if (!ctx) {
        return NULL;
    }
    OSSL_PARAM params[2];
    params[0] = OSSL_PARAM_construct_utf8_string(
        OSSL_PKEY_PARAM_GROUP_NAME, "prime256v1", 0);
    params[1] = OSSL_PARAM_construct_end();

    EVP_PKEY *key = NULL;
    if (EVP_PKEY_keygen_init(ctx) <= 0 ||
        EVP_PKEY_CTX_set_params(ctx, params) <= 0 ||
        EVP_PKEY_keygen(ctx, &key) <= 0) {
        EVP_PKEY_CTX_free(ctx);
        return NULL;
    }
    EVP_PKEY_CTX_free(ctx);
    return key;
}

static int add_extension(X509 *cert, X509 *issuer, int nid, const char *value) {
    X509V3_CTX ctx;
    X509V3_set_ctx_nodb(&ctx);
    X509V3_set_ctx(&ctx, issuer, cert, NULL, NULL, 0);
    X509_EXTENSION *extension = X509V3_EXT_conf_nid(NULL, &ctx, nid, value);
    if (!extension) {
        return 0;
    }
    int ok = X509_add_ext(cert, extension, -1);
    X509_EXTENSION_free(extension);
    return ok;
}

static int set_serial(X509 *cert) {
    unsigned char bytes[8];
    if (RAND_bytes(bytes, sizeof(bytes)) != 1) {
        return 0;
    }
    bytes[0] &= 0x7f;
    BIGNUM *number = BN_bin2bn(bytes, sizeof(bytes), NULL);
    if (!number) {
        return 0;
    }
    int ok = BN_to_ASN1_INTEGER(number, X509_get_serialNumber(cert)) != NULL;
    BN_free(number);
    return ok;
}

static X509_NAME *make_name(const char *common_name) {
    X509_NAME *name = X509_NAME_new();
    if (!name) {
        return NULL;
    }
    if (!X509_NAME_add_entry_by_NID(name, NID_countryName, MBSTRING_ASC,
                                    (unsigned char *)"US", -1, -1, 0) ||
        !X509_NAME_add_entry_by_NID(name, NID_organizationName, MBSTRING_ASC,
                                    (unsigned char *)"ShortSign", -1, -1, 0) ||
        !X509_NAME_add_entry_by_NID(name, NID_commonName, MBSTRING_ASC,
                                    (unsigned char *)common_name, -1, -1, 0)) {
        X509_NAME_free(name);
        return NULL;
    }
    return name;
}

static int shortcut_signing_oid(void) {
    int nid = OBJ_txt2nid("1.2.840.113635.100.18.1");
    if (nid == NID_undef) {
        nid = OBJ_create("1.2.840.113635.100.18.1",
                         "shortcutSigning", "shortcutSigning");
    }
    return nid;
}

static int set_validity(X509 *cert) {
    return X509_gmtime_adj(X509_getm_notBefore(cert), -86400) != NULL &&
           X509_gmtime_adj(X509_getm_notAfter(cert), 3650L * 86400) != NULL;
}

static int export_der(X509 *cert, void **out, size_t *outSize) {
    int length = i2d_X509(cert, NULL);
    if (length <= 0) {
        return 0;
    }
    unsigned char *buffer = malloc((size_t)length);
    if (!buffer) {
        return 0;
    }
    unsigned char *cursor = buffer;
    if (i2d_X509(cert, &cursor) != length) {
        free(buffer);
        return 0;
    }
    *out = buffer;
    *outSize = (size_t)length;
    return 1;
}

static int export_key(EVP_PKEY *key, void **out, size_t *outSize) {
    unsigned char public_key[65];
    size_t public_key_size = 0;
    if (EVP_PKEY_get_octet_string_param(key, OSSL_PKEY_PARAM_PUB_KEY,
                                        public_key, sizeof(public_key),
                                        &public_key_size) <= 0 ||
        public_key_size != sizeof(public_key)) {
        return 0;
    }

    BIGNUM *private_key = NULL;
    if (EVP_PKEY_get_bn_param(key, OSSL_PKEY_PARAM_PRIV_KEY, &private_key) <= 0 ||
        !private_key) {
        return 0;
    }

    unsigned char *buffer = malloc(sizeof(public_key) + 32);
    if (!buffer) {
        BN_free(private_key);
        return 0;
    }
    memcpy(buffer, public_key, sizeof(public_key));
    if (BN_bn2binpad(private_key, buffer + sizeof(public_key), 32) != 32) {
        free(buffer);
        BN_free(private_key);
        return 0;
    }
    BN_free(private_key);
    *out = buffer;
    *outSize = sizeof(public_key) + 32;
    return 1;
}

int shorts_create_identity(
    void **key, size_t *keySize,
    void **leafCert, size_t *leafSize,
    void **rootCert, size_t *rootSize)
{
    if (!key || !keySize || !leafCert || !leafSize || !rootCert || !rootSize) {
        return -1;
    }
    *key = NULL;
    *leafCert = NULL;
    *rootCert = NULL;
    *keySize = 0;
    *leafSize = 0;
    *rootSize = 0;

    EVP_PKEY *rootKey = generate_key();
    EVP_PKEY *leafKey = generate_key();
    X509 *root = NULL;
    X509 *leaf = NULL;
    X509_NAME *rootName = NULL;
    X509_NAME *leafName = NULL;
    int ok = 0;

    if (!rootKey || !leafKey) {
        goto done;
    }

    rootName = make_name("ShortSign Self-Signed Root");
    leafName = make_name("ShortSign Shortcut Signing");
    if (!rootName || !leafName) {
        goto done;
    }

    root = X509_new();
    if (!root ||
        !set_serial(root) ||
        !set_validity(root) ||
        !X509_set_version(root, 2) ||
        !X509_set_pubkey(root, rootKey) ||
        !X509_set_subject_name(root, rootName) ||
        !X509_set_issuer_name(root, rootName) ||
        !add_extension(root, root, NID_basic_constraints, "critical,CA:TRUE") ||
        !add_extension(root, root, NID_key_usage,
                       "critical,digitalSignature,keyCertSign,cRLSign") ||
        !add_extension(root, root, NID_subject_key_identifier, "hash") ||
        !add_extension(root, root, NID_authority_key_identifier, "keyid:always")) {
        goto done;
    }
    int oid = shortcut_signing_oid();
    if (oid != NID_undef) {
        add_extension(root, root, oid,
                      "ASN1:UTF8String:WithLoveFromShortSign");
    }

    leaf = X509_new();
    if (!leaf ||
        !set_serial(leaf) ||
        !set_validity(leaf) ||
        !X509_set_version(leaf, 2) ||
        !X509_set_pubkey(leaf, leafKey) ||
        !X509_set_subject_name(leaf, leafName) ||
        !X509_set_issuer_name(leaf, X509_get_subject_name(root)) ||
        !add_extension(leaf, root, NID_basic_constraints, "critical,CA:FALSE") ||
        !add_extension(leaf, root, NID_key_usage,
                       "critical,digitalSignature,keyEncipherment") ||
        !add_extension(leaf, root, NID_ext_key_usage,
                       "serverAuth,clientAuth") ||
        !add_extension(leaf, root, NID_subject_key_identifier, "hash") ||
        !add_extension(leaf, root, NID_authority_key_identifier, "keyid:always")) {
        goto done;
    }
    if (oid != NID_undef) {
        add_extension(leaf, root, oid,
                      "ASN1:UTF8String:WithLoveFromShortSign");
    }

    if (!X509_sign(root, rootKey, EVP_sha256()) ||
        !X509_sign(leaf, rootKey, EVP_sha256())) {
        goto done;
    }

    if (!export_key(leafKey, key, keySize) ||
        !export_der(leaf, leafCert, leafSize) ||
        !export_der(root, rootCert, rootSize)) {
        goto done;
    }
    ok = 1;

done:
    if (!ok) {
        free(*key);
        free(*leafCert);
        free(*rootCert);
        *key = NULL;
        *leafCert = NULL;
        *rootCert = NULL;
        *keySize = 0;
        *leafSize = 0;
        *rootSize = 0;
    }
    X509_free(root);
    X509_free(leaf);
    X509_NAME_free(rootName);
    X509_NAME_free(leafName);
    EVP_PKEY_free(rootKey);
    EVP_PKEY_free(leafKey);
    return ok ? 0 : -1;
}

int shorts_certificate_dates(
    const void *der, size_t derSize,
    long long *notBefore, long long *notAfter)
{
    if (!der || !notBefore || !notAfter) {
        return -1;
    }
    const unsigned char *cursor = der;
    X509 *certificate = d2i_X509(NULL, &cursor, (long)derSize);
    if (!certificate) {
        return -1;
    }

    int ok = 1;
    int days = 0;
    int seconds = 0;
    time_t now = time(NULL);

    if (ASN1_TIME_diff(&days, &seconds, NULL,
                       X509_getm_notBefore(certificate)) != 1) {
        ok = 0;
    } else {
        *notBefore = (long long)now + (long long)days * 86400 + seconds;
    }

    days = 0;
    seconds = 0;
    if (ASN1_TIME_diff(&days, &seconds, NULL,
                       X509_getm_notAfter(certificate)) != 1) {
        ok = 0;
    } else {
        *notAfter = (long long)now + (long long)days * 86400 + seconds;
    }

    X509_free(certificate);
    return ok ? 0 : -1;
}
