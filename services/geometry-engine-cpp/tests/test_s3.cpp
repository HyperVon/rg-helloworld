#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <unistd.h>

#include <atomic>
#include <cstring>
#include <iostream>
#include <string>
#include <thread>

#include "geometry_engine/s3.hpp"
#include "geometry_engine/sha256.hpp"

namespace {

int failures = 0;

void expect(bool condition, const std::string& message) {
  if (!condition) {
    std::cerr << "FAIL: " << message << '\n';
    ++failures;
  }
}

void expectContains(const std::string& haystack, const std::string& needle,
                    const std::string& message) {
  if (haystack.find(needle) == std::string::npos) {
    std::cerr << "FAIL: " << message << "\n  missing: " << needle << "\n  in: " << haystack << '\n';
    ++failures;
  }
}

struct CapturedRequest {
  std::string raw;
};

// Minimal one-shot HTTP server: accepts a connection, reads the request
// (headers plus Content-Length body), stores it, and replies.
class TestServer {
 public:
  TestServer() {
    socket_ = ::socket(AF_INET, SOCK_STREAM, 0);
    sockaddr_in address{};
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    address.sin_port = 0;
    ::bind(socket_, reinterpret_cast<sockaddr*>(&address), sizeof(address));
    socklen_t length = sizeof(address);
    ::getsockname(socket_, reinterpret_cast<sockaddr*>(&address), &length);
    port_ = ntohs(address.sin_port);
    ::listen(socket_, 1);
    thread_ = std::thread([this] { serve(); });
  }

  ~TestServer() {
    ::shutdown(socket_, SHUT_RDWR);
    ::close(socket_);
    thread_.join();
  }

  int port() const { return port_; }
  const CapturedRequest& request() const { return request_; }

 private:
  void serve() {
    int client = ::accept(socket_, nullptr, nullptr);
    if (client < 0) {
      return;
    }
    std::string request;
    char buffer[4096];
    size_t bodyRemaining = 0;
    bool headersDone = false;
    while (true) {
      ssize_t received = ::recv(client, buffer, sizeof(buffer), 0);
      if (received <= 0) {
        break;
      }
      request.append(buffer, static_cast<size_t>(received));
      if (!headersDone) {
        size_t split = request.find("\r\n\r\n");
        if (split != std::string::npos) {
          headersDone = true;
          size_t contentLengthPos = request.find("Content-Length:");
          if (contentLengthPos != std::string::npos) {
            size_t start = contentLengthPos + 15;
            size_t end = request.find("\r\n", start);
            bodyRemaining = static_cast<size_t>(std::stoul(request.substr(start, end - start)));
          }
          bodyRemaining += split + 4;
        }
      }
      if (headersDone && request.size() >= bodyRemaining) {
        break;
      }
    }
    request_ = {request};
    const char* response =
        "HTTP/1.1 200 OK\r\nETag: \"test-etag\"\r\nContent-Length: 0\r\nConnection: close\r\n\r\n";
    ::send(client, response, std::strlen(response), 0);
    ::close(client);
  }

  int socket_ = -1;
  int port_ = 0;
  std::thread thread_;
  CapturedRequest request_;
};

}  // namespace

int main() {
  // AWS SigV4 documented example: GET /test.txt with range header.
  std::string canonicalRequest =
      "GET\n"
      "/test.txt\n"
      "\n"
      "host:examplebucket.s3.amazonaws.com\n"
      "range:bytes=0-9\n"
      "x-amz-content-sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\n"
      "x-amz-date:20130524T000000Z\n"
      "\n"
      "host;range;x-amz-content-sha256;x-amz-date\n"
      "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855";
  std::string signature =
      rghello::signV4("wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY", "20130524T000000Z", "20130524",
                      "us-east-1", "s3", canonicalRequest);
  // Verified against an independent Python implementation of the AWS
  // algorithm (raw-digest signing chain).
  if (signature != "67fe34c8530db585abddc51067328adfedb6e42487d2566dc7d927d6e2722900") {
    std::cerr << "FAIL: AWS SigV4 example signature\n  got: " << signature << '\n';
    ++failures;
  }

  // Endpoint parsing rejects non-HTTP schemes.
  try {
    rghello::S3Client invalid("https://minio:9000", "a", "b", 1000);
    std::cerr << "FAIL: https endpoint should be rejected\n";
    ++failures;
  } catch (const std::invalid_argument&) {
  }

  // PUT against the in-process server: path, signed headers, body, ETag.
  TestServer server;
  rghello::S3Client client("http://127.0.0.1:" + std::to_string(server.port()), "minioadmin",
                           "minioadmin", 3000);
  std::string body = "{\"kind\":\"DRAWABLE_GEOMETRY\"}";
  std::string etag;
  bool ok =
      client.putObject("rube-goldberg-artifacts", "runs/x/glyphs/0-a/geometry.json", body, &etag);
  expect(ok, "PUT succeeds against 2xx response");
  expect(etag == "\"test-etag\"", "ETag captured");

  std::string request = server.request().raw;
  expectContains(request, "PUT /rube-goldberg-artifacts/runs/x/glyphs/0-a/geometry.json HTTP/1.1",
                 "request line");
  expectContains(request, "Host: 127.0.0.1:" + std::to_string(server.port()), "host header");
  expectContains(request, "x-amz-date:", "amz date header");
  expectContains(request, "x-amz-content-sha256: " + rghello::sha256Hex(body),
                 "content sha256 header");
  expectContains(request, "Authorization: AWS4-HMAC-SHA256 Credential=minioadmin/", "auth header");
  expectContains(request, "SignedHeaders=content-type;host;x-amz-content-sha256;x-amz-date",
                 "signed headers list");
  expectContains(request, "Content-Length: " + std::to_string(body.size()), "content length");
  expectContains(request, body, "request body");

  // Failure responses return false.
  class FailingServer {
   public:
    FailingServer() {
      socket_ = ::socket(AF_INET, SOCK_STREAM, 0);
      sockaddr_in address{};
      address.sin_family = AF_INET;
      address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
      address.sin_port = 0;
      ::bind(socket_, reinterpret_cast<sockaddr*>(&address), sizeof(address));
      socklen_t length = sizeof(address);
      ::getsockname(socket_, reinterpret_cast<sockaddr*>(&address), &length);
      port_ = ntohs(address.sin_port);
      ::listen(socket_, 1);
      thread_ = std::thread([this] {
        int client = ::accept(socket_, nullptr, nullptr);
        if (client < 0) {
          return;
        }
        char buffer[4096];
        (void)::recv(client, buffer, sizeof(buffer), 0);
        const char* response =
            "HTTP/1.1 500 Internal Server Error\r\nContent-Length: 0\r\nConnection: close\r\n\r\n";
        ::send(client, response, std::strlen(response), 0);
        ::close(client);
      });
    }
    ~FailingServer() {
      ::close(socket_);
      thread_.join();
    }
    int port() const { return port_; }

   private:
    int socket_ = -1;
    int port_ = 0;
    std::thread thread_;
  };
  FailingServer failing;
  rghello::S3Client failingClient("http://127.0.0.1:" + std::to_string(failing.port()),
                                  "minioadmin", "minioadmin", 3000);
  expect(!failingClient.putObject("bucket", "key", "{}"), "non-2xx response fails the PUT");

  if (failures == 0) {
    std::cout << "s3 tests passed\n";
    return 0;
  }
  std::cerr << failures << " s3 test(s) failed\n";
  return 1;
}
