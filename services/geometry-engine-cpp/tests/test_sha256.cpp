#include <iostream>
#include <string>

#include "geometry_engine/sha256.hpp"

namespace {

int failures = 0;

void expectEq(const std::string& actual, const std::string& expected, const std::string& message) {
  if (actual != expected) {
    std::cerr << "FAIL: " << message << "\n  expected: " << expected << "\n  actual:   " << actual
              << '\n';
    ++failures;
  }
}

std::string repeat(char c, size_t count) { return std::string(count, c); }

}  // namespace

int main() {
  // FIPS 180-4 known-answer vectors.
  expectEq(rghw::sha256Hex(""),
           "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "SHA-256 of empty");
  expectEq(rghw::sha256Hex("abc"),
           "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "SHA-256 of abc");
  expectEq(rghw::sha256Hex("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"),
           "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1",
           "SHA-256 of two-block message");
  expectEq(rghw::sha256Hex(repeat('a', 1000000)),
           "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0",
           "SHA-256 of one million a's");

  // RFC 4231 HMAC-SHA256 test cases.
  expectEq(rghw::hmacSha256Hex(repeat(static_cast<char>(0x0b), 20), "Hi There"),
           "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7",
           "HMAC-SHA256 case 1");
  expectEq(rghw::hmacSha256Hex("Jefe", "what do ya want for nothing?"),
           "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843",
           "HMAC-SHA256 case 2");
  expectEq(rghw::hmacSha256Hex(repeat(static_cast<char>(0xaa), 20),
                                  std::string(50, static_cast<char>(0xdd))),
           "773ea91e36800e46854db8ebd09181a72959098b3ef8c122d9635514ced565fe",
           "HMAC-SHA256 case 3");
  // Key longer than one block (64 bytes) must be hashed first.
  expectEq(rghw::hmacSha256Hex(repeat(static_cast<char>(0xaa), 131),
                                  "Test Using Larger Than Block-Size Key - Hash Key First"),
           "60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54",
           "HMAC-SHA256 long key");

  if (failures == 0) {
    std::cout << "sha256 tests passed\n";
    return 0;
  }
  std::cerr << failures << " sha256 test(s) failed\n";
  return 1;
}
