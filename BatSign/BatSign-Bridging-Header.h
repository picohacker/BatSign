//
//  BatSign-Bridging-Header.h
//  BatSign
//

#import "BatSignBridge.h"

// libzstd (linked from Vendor/zstd/lib, headers in Vendor/zstd/include) —
// unpacks .deb tweaks whose data.tar is zstd-compressed (dpkg default).
#include "zstd.h"
