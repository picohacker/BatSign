// Test harness driving the BatSign bridge directly.
#include "BatSignBridge.h"
#include <cstdio>

static void log_cb(const char* line, void*) { fputs(line, stdout); }

int main(int argc, char** argv) {
    if (argc < 3) { printf("usage: %s in.ipa out.ipa [cert.p12 password profile]\n", argv[0]); return 2; }
    batsign_set_log_callback(log_cb, nullptr);
    const char* p12 = argc > 3 ? argv[3] : nullptr;
    const char* pass = argc > 4 ? argv[4] : nullptr;
    const char* prov = argc > 5 ? argv[5] : nullptr;
    int rc = batsign_sign_ipa(argv[1], argv[2], p12, prov, pass,
                              nullptr,       // entitlements
                              argc > 6 ? argv[6] : nullptr,   // bundle id
                              nullptr,       // version
                              argc > 7 ? argv[7] : nullptr,   // display name
                              nullptr,
                              nullptr, 0, nullptr, 0,
                              p12 == nullptr ? 1 : 0,  // adhoc when no cert
                              0, 0, 0, 0, 0, 0, 9, "/tmp");
    printf("\nENGINE RESULT: %d\n", rc);
    return rc == 0 ? 0 : 1;
}
