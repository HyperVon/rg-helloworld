#ifndef RGHELLO_GEOMETRY_ENGINE_S3_HPP_
#define RGHELLO_GEOMETRY_ENGINE_S3_HPP_

#include <string>

#include "geometry_engine/service.hpp"

namespace rghello {

// Computes the AWS Signature Version 4 request signature for a canonical
// request (AWS docs "Signature Calculations for the Authorization Header").
// Exposed for known-answer tests.
std::string signV4(const std::string& secretKey, const std::string& amzDate,
                   const std::string& dateStamp, const std::string& region,
                   const std::string& service, const std::string& canonicalRequest);

// Minimal MinIO/S3 client: AWS SigV4-signed PUT over plain POSIX sockets.
// Local MinIO is plaintext HTTP; TLS and full S3 API coverage are out of
// scope for the local acceptance environment.
class S3Client : public ObjectStore {
 public:
  // endpoint must be "http://host:port".
  S3Client(std::string endpoint, std::string accessKey, std::string secretKey, int timeoutMs);

  bool putObject(const std::string& bucket, const std::string& key, const std::string& body,
                 std::string* etagOut = nullptr) override;

  const std::string& endpoint() const { return endpoint_; }

 private:
  std::string endpoint_;
  std::string host_;
  int port_ = 9000;
  std::string accessKey_;
  std::string secretKey_;
  int timeoutMs_;
};

}  // namespace rghello

#endif  // RGHELLO_GEOMETRY_ENGINE_S3_HPP_
