//
//  BatSignBridge.h
//  BatSign
//
//  C bridge over the vendored zsign engine (MIT, © zhlynn).
//  The Swift app talks to the signing engine exclusively through this header.
//

#ifndef BATSIGN_BRIDGE_H
#define BATSIGN_BRIDGE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*batsign_log_cb)(const char* line, void* context);

enum {
	BATSIGN_OK = 0,
	BATSIGN_ERR_ARGS = -1,     ///< missing/invalid input, output, temp folder, dylib
	BATSIGN_ERR_INIT = -2,     ///< certificate/profile could not be loaded (wrong password?)
	BATSIGN_ERR_EXTRACT = -3,  ///< ipa could not be unzipped
	BATSIGN_ERR_SIGN = -4,     ///< the signing pass failed
	BATSIGN_ERR_PAYLOAD = -5,  ///< no Payload/<App>.app found after signing
	BATSIGN_ERR_ARCHIVE = -6   ///< re-zipping into the output ipa failed
};

/// Install (or clear, with NULL) the log callback invoked for every engine log line.
void batsign_set_log_callback(batsign_log_cb cb, void* context);

/// Sign an .ipa file in-place into `out_ipa`.
///
/// All paths are absolute, UTF-8 encoded. `cert_p12`, `prov_profile` and `password`
/// may be NULL when `adhoc` is non-zero. Optional parameters may be NULL or empty
/// to leave the app unmodified.
///
/// `icon_png` replaces the app icon (must be a real PNG).
/// `info_plist_overrides_file` is an XML plist whose top-level keys are merged
/// into the app's Info.plist before signing.
///
/// Returns one of the BATSIGN_* result codes.
int batsign_sign_ipa(const char* in_ipa,
                     const char* out_ipa,
                     const char* cert_p12,
                     const char* prov_profile,
                     const char* password,
                     const char* entitlements_path,
                     const char* bundle_id,
                     const char* bundle_version,
                     const char* display_name,
                     const char* min_version,
                     const char* const* dylibs, int dylib_count,
                     const char* const* remove_dylib_names, int remove_dylib_count,
                     int adhoc,
                     int weak_inject,
                     int remove_extensions,
                     int remove_watch,
                     int remove_provision,
                     int remove_supported_devices,
                     int enable_documents,
                     int zip_level,
                     const char* temp_folder,
                     const char* icon_png,
                     const char* info_plist_overrides_file);

#ifdef __cplusplus
}
#endif

#endif /* BATSIGN_BRIDGE_H */
