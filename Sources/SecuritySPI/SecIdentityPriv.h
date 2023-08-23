#ifndef _SECURITY_SECIDENTITYPRIV_H_
#define _SECURITY_SECIDENTITYPRIV_H_

#import <Security/SecBase.h>

SecIdentityRef SecIdentityCreate(
     CFAllocatorRef allocator,
     SecCertificateRef certificate,
     SecKeyRef privateKey) CF_RETURNS_RETAINED;

#endif /* _SECURITY_SECIDENTITYPRIV_H_ */
