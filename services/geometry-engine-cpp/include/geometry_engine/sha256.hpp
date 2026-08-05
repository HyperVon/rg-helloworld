#ifndef RGHELLO_GEOMETRY_ENGINE_SHA256_HPP_
#define RGHELLO_GEOMETRY_ENGINE_SHA256_HPP_

#include <cstddef>
#include <cstdint>
#include <string>

namespace rghello {

// FIPS 180-4 SHA-256 with hex encoding, used for artifact checksums and the
// AWS SigV4 signing chain. Self-contained so the geometry engine has no
// OpenSSL dependency.
std::string sha256Hex(const std::string& data);

// RFC 2104 HMAC-SHA256 returning the raw 32-byte digest. The SigV4 signing
// chain passes raw digests between HMAC steps.
std::string hmacSha256(const std::string& key, const std::string& data);

// RFC 2104 HMAC-SHA256, hex encoded.
std::string hmacSha256Hex(const std::string& key, const std::string& data);

}  // namespace rghello

#endif  // RGHELLO_GEOMETRY_ENGINE_SHA256_HPP_
