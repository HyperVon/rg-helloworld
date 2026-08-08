#include "geometry_engine/s3.hpp"

#include <arpa/inet.h>
#include <netdb.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <unistd.h>

#include <cstdio>
#include <cstring>
#include <ctime>
#include <stdexcept>
#include <string>

#include "geometry_engine/sha256.hpp"

namespace rghw {

namespace {

constexpr char kRegion[] = "us-east-1";
constexpr char kService[] = "s3";
constexpr char kAlgorithm[] = "AWS4-HMAC-SHA256";

std::string uriEncode(const std::string& value) {
  const char* hex = "0123456789ABCDEF";
  std::string out;
  for (unsigned char c : value) {
    if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-' ||
        c == '_' || c == '.' || c == '~') {
      out.push_back(static_cast<char>(c));
    } else {
      out.push_back('%');
      out.push_back(hex[c >> 4]);
      out.push_back(hex[c & 0x0F]);
    }
  }
  return out;
}

// Object keys are path-style: '/' separates segments and must survive.
std::string encodeKey(const std::string& key) {
  std::string out;
  size_t start = 0;
  while (true) {
    size_t slash = key.find('/', start);
    std::string segment =
        key.substr(start, slash == std::string::npos ? std::string::npos : slash - start);
    out += uriEncode(segment);
    if (slash == std::string::npos) {
      break;
    }
    out.push_back('/');
    start = slash + 1;
  }
  return out;
}

}  // namespace

std::string signV4(const std::string& secretKey, const std::string& amzDate,
                   const std::string& dateStamp, const std::string& region,
                   const std::string& service, const std::string& canonicalRequest) {
  std::string stringToSign = std::string(kAlgorithm) + "\n" + amzDate + "\n" + dateStamp + "/" +
                             region + "/" + service + "/aws4_request\n" +
                             sha256Hex(canonicalRequest);
  // The signing chain passes raw digests between HMAC steps, not hex.
  std::string key = "AWS4" + secretKey;
  std::string kDate = hmacSha256(key, dateStamp);
  std::string kRegion = hmacSha256(kDate, region);
  std::string kService = hmacSha256(kRegion, service);
  std::string kSigning = hmacSha256(kService, "aws4_request");
  return hmacSha256Hex(kSigning, stringToSign);
}

S3Client::S3Client(std::string endpoint, std::string accessKey, std::string secretKey,
                   int timeoutMs)
    : endpoint_(std::move(endpoint)),
      accessKey_(std::move(accessKey)),
      secretKey_(std::move(secretKey)),
      timeoutMs_(timeoutMs) {
  const std::string prefix = "http://";
  if (endpoint_.rfind(prefix, 0) != 0) {
    throw std::invalid_argument("S3 endpoint must start with http://");
  }
  std::string rest = endpoint_.substr(prefix.size());
  size_t colon = rest.rfind(':');
  if (colon == std::string::npos) {
    host_ = rest;
    port_ = 80;
  } else {
    host_ = rest.substr(0, colon);
    port_ = std::stoi(rest.substr(colon + 1));
  }
}

bool S3Client::putObject(const std::string& bucket, const std::string& key, const std::string& body,
                         std::string* etagOut) {
  char dateBuffer[32];
  time_t now = time(nullptr);
  struct tm tmUtc{};
  gmtime_r(&now, &tmUtc);
  strftime(dateBuffer, sizeof(dateBuffer), "%Y%m%dT%H%M%SZ", &tmUtc);
  std::string amzDate(dateBuffer);
  std::string dateStamp(amzDate, 0, 8);

  std::string payloadHash = sha256Hex(body);
  std::string canonicalUri = "/" + bucket + "/" + encodeKey(key);
  std::string canonicalHeaders = "content-type:application/json\nhost:" + host_ + ":" +
                                 std::to_string(port_) + "\nx-amz-content-sha256:" + payloadHash +
                                 "\nx-amz-date:" + amzDate + "\n";
  std::string signedHeaders = "content-type;host;x-amz-content-sha256;x-amz-date";
  std::string canonicalRequest = "PUT\n" + canonicalUri + "\n\n" + canonicalHeaders + "\n" +
                                 signedHeaders + "\n" + payloadHash;
  std::string signature =
      signV4(secretKey_, amzDate, dateStamp, kRegion, kService, canonicalRequest);
  std::string authorization = std::string(kAlgorithm) + " Credential=" + accessKey_ + "/" +
                              dateStamp + "/" + kRegion + "/" + kService + "/aws4_request, " +
                              "SignedHeaders=" + signedHeaders + ", Signature=" + signature;

  int sock = socket(AF_INET, SOCK_STREAM, 0);
  if (sock < 0) {
    return false;
  }
  struct addrinfo hints{};
  hints.ai_family = AF_INET;
  hints.ai_socktype = SOCK_STREAM;
  struct addrinfo* addresses = nullptr;
  if (getaddrinfo(host_.c_str(), nullptr, &hints, &addresses) != 0 || addresses == nullptr) {
    close(sock);
    return false;
  }
  struct sockaddr_in server{};
  server.sin_family = AF_INET;
  server.sin_port = htons(static_cast<uint16_t>(port_));
  server.sin_addr = reinterpret_cast<struct sockaddr_in*>(addresses->ai_addr)->sin_addr;
  freeaddrinfo(addresses);
  if (connect(sock, reinterpret_cast<struct sockaddr*>(&server), sizeof(server)) != 0) {
    close(sock);
    return false;
  }
  struct timeval timeout{};
  timeout.tv_sec = timeoutMs_ / 1000;
  timeout.tv_usec = (timeoutMs_ % 1000) * 1000;
  setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
  setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));

  std::string request = "PUT " + canonicalUri + " HTTP/1.1\r\n";
  request += "Host: " + host_ + ":" + std::to_string(port_) + "\r\n";
  request += "Content-Type: application/json\r\n";
  request += "x-amz-content-sha256: " + payloadHash + "\r\n";
  request += "x-amz-date: " + amzDate + "\r\n";
  request += "Authorization: " + authorization + "\r\n";
  request += "Content-Length: " + std::to_string(body.size()) + "\r\n";
  request += "Connection: close\r\n\r\n";
  request += body;

  size_t sent = 0;
  while (sent < request.size()) {
    ssize_t written = send(sock, request.data() + sent, request.size() - sent, 0);
    if (written <= 0) {
      close(sock);
      return false;
    }
    sent += static_cast<size_t>(written);
  }

  std::string response;
  char buffer[4096];
  while (true) {
    ssize_t received = recv(sock, buffer, sizeof(buffer), 0);
    if (received <= 0) {
      break;
    }
    response.append(buffer, static_cast<size_t>(received));
  }
  close(sock);

  if (response.rfind("HTTP/1.1 ", 0) != 0) {
    return false;
  }
  int status = 0;
  std::sscanf(response.c_str() + 9, "%d", &status);
  if (status < 200 || status >= 300) {
    return false;
  }
  if (etagOut != nullptr) {
    size_t etagPos = response.find("\r\nETag:");
    if (etagPos != std::string::npos) {
      size_t start = etagPos + 7;
      while (start < response.size() && (response[start] == ' ' || response[start] == '\t')) {
        ++start;
      }
      size_t end = response.find("\r\n", start);
      *etagOut = response.substr(start, end - start);
    }
  }
  return true;
}

}  // namespace rghw
