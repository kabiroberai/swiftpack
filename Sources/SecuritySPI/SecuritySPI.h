// These files are taken directly from Apple's open-source Security project:
// https://github.com/apple-oss-distributions/Security
// with minor tweaks to the include directives.
#import "SecCodeSigner.h"
// These two headers are in the macOS SDK but not in other Darwin SDKs.
#import "SecStaticCode.h"
#import "SecCode.h"

// We don't use the entirety of SecIdentityPriv.h so to keep it simple we've
// slimmed this file down to only the necessary bits.
#import "SecIdentityPriv.h"
