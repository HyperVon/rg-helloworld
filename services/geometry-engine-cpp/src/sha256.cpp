#include "geometry_engine/sha256.hpp"

#include <array>
#include <cstring>

namespace rghello {

namespace {

constexpr std::array<uint32_t, 64> kRoundConstants = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2};

struct Sha256 {
  std::array<uint32_t, 8> state = {0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
                                   0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19};
  std::array<uint8_t, 64> buffer{};
  uint64_t length = 0;

  void update(const uint8_t* data, size_t size) {
    size_t bufferBytes = static_cast<size_t>(length) % 64;
    length += size;
    if (bufferBytes != 0) {
      size_t fill = 64 - bufferBytes;
      if (size < fill) {
        std::memcpy(buffer.data() + bufferBytes, data, size);
        return;
      }
      std::memcpy(buffer.data() + bufferBytes, data, fill);
      transform(buffer.data());
      data += fill;
      size -= fill;
    }
    while (size >= 64) {
      transform(data);
      data += 64;
      size -= 64;
    }
    std::memcpy(buffer.data(), data, size);
  }

  void finalize(std::array<uint8_t, 32>& out) {
    uint64_t bitLength = length * 8;
    size_t bufferBytes = static_cast<size_t>(length) % 64;
    buffer[bufferBytes++] = 0x80;
    if (bufferBytes > 56) {
      std::memset(buffer.data() + bufferBytes, 0, 64 - bufferBytes);
      transform(buffer.data());
      bufferBytes = 0;
    }
    std::memset(buffer.data() + bufferBytes, 0, 56 - bufferBytes);
    for (int i = 0; i < 8; ++i) {
      buffer[63 - i] = static_cast<uint8_t>(bitLength >> (8 * i));
    }
    transform(buffer.data());
    for (int i = 0; i < 8; ++i) {
      out[4 * i] = static_cast<uint8_t>(state[i] >> 24);
      out[4 * i + 1] = static_cast<uint8_t>(state[i] >> 16);
      out[4 * i + 2] = static_cast<uint8_t>(state[i] >> 8);
      out[4 * i + 3] = static_cast<uint8_t>(state[i]);
    }
  }

  static uint32_t rotr(uint32_t value, int bits) {
    return (value >> bits) | (value << (32 - bits));
  }

  void transform(const uint8_t* block) {
    std::array<uint32_t, 64> w{};
    for (int i = 0; i < 16; ++i) {
      w[i] = (static_cast<uint32_t>(block[4 * i]) << 24) |
             (static_cast<uint32_t>(block[4 * i + 1]) << 16) |
             (static_cast<uint32_t>(block[4 * i + 2]) << 8) |
             static_cast<uint32_t>(block[4 * i + 3]);
    }
    for (int i = 16; i < 64; ++i) {
      uint32_t s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
      uint32_t s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
      w[i] = w[i - 16] + s0 + w[i - 7] + s1;
    }
    uint32_t a = state[0];
    uint32_t b = state[1];
    uint32_t c = state[2];
    uint32_t d = state[3];
    uint32_t e = state[4];
    uint32_t f = state[5];
    uint32_t g = state[6];
    uint32_t h = state[7];
    for (int i = 0; i < 64; ++i) {
      uint32_t s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
      uint32_t ch = (e & f) ^ (~e & g);
      uint32_t temp1 = h + s1 + ch + kRoundConstants[i] + w[i];
      uint32_t s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
      uint32_t maj = (a & b) ^ (a & c) ^ (b & c);
      uint32_t temp2 = s0 + maj;
      h = g;
      g = f;
      f = e;
      e = d + temp1;
      d = c;
      c = b;
      b = a;
      a = temp1 + temp2;
    }
    state[0] += a;
    state[1] += b;
    state[2] += c;
    state[3] += d;
    state[4] += e;
    state[5] += f;
    state[6] += g;
    state[7] += h;
  }
};

std::string toHex(const std::array<uint8_t, 32>& bytes) {
  const char* digits = "0123456789abcdef";
  std::string out;
  out.reserve(64);
  for (uint8_t byte : bytes) {
    out.push_back(digits[byte >> 4]);
    out.push_back(digits[byte & 0x0F]);
  }
  return out;
}

}  // namespace

std::string sha256Hex(const std::string& data) {
  Sha256 hasher;
  hasher.update(reinterpret_cast<const uint8_t*>(data.data()), data.size());
  std::array<uint8_t, 32> digest{};
  hasher.finalize(digest);
  return toHex(digest);
}

std::string hmacSha256(const std::string& key, const std::string& data) {
  std::array<uint8_t, 64> keyBlock{};
  if (key.size() > 64) {
    Sha256 hasher;
    hasher.update(reinterpret_cast<const uint8_t*>(key.data()), key.size());
    std::array<uint8_t, 32> digest{};
    hasher.finalize(digest);
    std::memcpy(keyBlock.data(), digest.data(), 32);
  } else {
    std::memcpy(keyBlock.data(), key.data(), key.size());
  }
  std::array<uint8_t, 64> innerPad{};
  std::array<uint8_t, 64> outerPad{};
  for (size_t i = 0; i < 64; ++i) {
    innerPad[i] = keyBlock[i] ^ 0x36;
    outerPad[i] = keyBlock[i] ^ 0x5c;
  }
  Sha256 inner;
  inner.update(innerPad.data(), innerPad.size());
  inner.update(reinterpret_cast<const uint8_t*>(data.data()), data.size());
  std::array<uint8_t, 32> innerDigest{};
  inner.finalize(innerDigest);
  Sha256 outer;
  outer.update(outerPad.data(), outerPad.size());
  outer.update(innerDigest.data(), innerDigest.size());
  std::array<uint8_t, 32> digest{};
  outer.finalize(digest);
  return std::string(reinterpret_cast<const char*>(digest.data()), digest.size());
}

std::string hmacSha256Hex(const std::string& key, const std::string& data) {
  std::string raw = hmacSha256(key, data);
  std::array<uint8_t, 32> digest{};
  std::memcpy(digest.data(), raw.data(), raw.size());
  return toHex(digest);
}

}  // namespace rghello
