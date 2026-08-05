#ifndef RGHELLO_GEOMETRY_ENGINE_KAFKA_HPP_
#define RGHELLO_GEOMETRY_ENGINE_KAFKA_HPP_

#include <string>
#include <vector>

#include "geometry_engine/service.hpp"

namespace rghello {

// Thin librdkafka wrapper: one consumer group on the input topic and a
// producer for the output topic. Blocking poll with manual offset commit so
// processing is at-least-once and idempotent.
class KafkaClient : public KafkaTransport {
 public:
  KafkaClient(std::string bootstrap, std::string groupId, int pollTimeoutMs);
  ~KafkaClient() override;

  KafkaClient(const KafkaClient&) = delete;
  KafkaClient& operator=(const KafkaClient&) = delete;

  void subscribe(const std::vector<std::string>& topics);
  // Blocks up to the poll timeout. Returns false on timeout.
  bool poll(std::string* message) override;
  void commit();
  bool produce(const std::string& topic, const std::string& key, const std::string& value) override;

 private:
  struct Impl;
  Impl* impl_;
};

}  // namespace rghello

#endif  // RGHELLO_GEOMETRY_ENGINE_KAFKA_HPP_
