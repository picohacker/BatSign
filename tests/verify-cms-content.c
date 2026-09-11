#include <openssl/cms.h>
#include <openssl/err.h>
#include <openssl/bio.h>
#include <stdio.h>
int main(void) {
    BIO* f = BIO_new_file("/tmp/bat_engine_test/test.mobileprovision", "rb");
    CMS_ContentInfo* cms = d2i_CMS_bio(f, NULL);
    if (!cms) {
        printf("d2i FAILED:\n");
        ERR_print_errors_fp(stdout);
        return 1;
    }
    ASN1_OCTET_STRING** pos = CMS_get0_content(cms);
    printf("d2i OK; content ptr=%p len=%d\n", (void*)*pos, *pos ? ASN1_STRING_length(*pos) : -1);
    return 0;
}
