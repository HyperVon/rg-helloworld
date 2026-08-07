#include "geometry_engine/kafka.hpp"

#include <rdkafka.h>

#include <cstring>
#include <stdexcept>

namespace rghw {

struct KafkaClient::Impl {
  rd_kafka_t* consumer = nullptr;
  rd_kafka_t* producer = nullptr;
  rd_kafka_topic_partition_list_t* assignment = nullptr;
  int pollTimeoutMs = 1000;
  std::string lastMessage;
};

KafkaClient::KafkaClient(std::string bootstrap, std::string groupId, int pollTimeoutMs)
    : impl_(new Impl) {
  impl_->pollTimeoutMs = pollTimeoutMs;
  char errstr[512];
  rd_kafka_conf_t* consumerConf = rd_kafka_conf_new();
  rd_kafka_conf_set(consumerConf, "bootstrap.servers", bootstrap.c_str(), errstr, sizeof(errstr));
  rd_kafka_conf_set(consumerConf, "group.id", groupId.c_str(), errstr, sizeof(errstr));
  rd_kafka_conf_set(consumerConf, "enable.auto.commit", "false", errstr, sizeof(errstr));
  rd_kafka_conf_set(consumerConf, "auto.offset.reset", "earliest", errstr, sizeof(errstr));
  impl_->consumer = rd_kafka_new(RD_KAFKA_CONSUMER, consumerConf, errstr, sizeof(errstr));
  if (impl_->consumer == nullptr) {
    delete impl_;
    impl_ = nullptr;
    throw std::runtime_error(std::string("failed to create consumer: ") + errstr);
  }

  rd_kafka_conf_t* producerConf = rd_kafka_conf_new();
  rd_kafka_conf_set(producerConf, "bootstrap.servers", bootstrap.c_str(), errstr, sizeof(errstr));
  rd_kafka_conf_set(producerConf, "acks", "all", errstr, sizeof(errstr));
  impl_->producer = rd_kafka_new(RD_KAFKA_PRODUCER, producerConf, errstr, sizeof(errstr));
  if (impl_->producer == nullptr) {
    delete impl_;
    impl_ = nullptr;
    throw std::runtime_error(std::string("failed to create producer: ") + errstr);
  }
}

KafkaClient::~KafkaClient() {
  if (impl_ == nullptr) {
    return;
  }
  if (impl_->consumer != nullptr) {
    if (impl_->assignment != nullptr) {
      rd_kafka_commit(impl_->consumer, impl_->assignment, 0);
    }
    rd_kafka_consumer_close(impl_->consumer);
    rd_kafka_destroy(impl_->consumer);
  }
  if (impl_->producer != nullptr) {
    rd_kafka_destroy(impl_->producer);
  }
  delete impl_;
}

void KafkaClient::subscribe(const std::vector<std::string>& topics) {
  rd_kafka_topic_partition_list_t* list =
      rd_kafka_topic_partition_list_new(static_cast<int>(topics.size()));
  for (const std::string& topic : topics) {
    rd_kafka_topic_partition_list_add(list, topic.c_str(), RD_KAFKA_PARTITION_UA);
  }
  rd_kafka_subscribe(impl_->consumer, list);
  rd_kafka_topic_partition_list_destroy(list);
}

bool KafkaClient::poll(std::string* message) {
  rd_kafka_message_t* record = rd_kafka_consumer_poll(impl_->consumer, impl_->pollTimeoutMs);
  if (record == nullptr) {
    return false;
  }
  if (record->err != 0) {
    rd_kafka_message_destroy(record);
    return false;
  }
  if (record->payload != nullptr && record->len > 0) {
    impl_->lastMessage.assign(static_cast<const char*>(record->payload), record->len);
    *message = impl_->lastMessage;
  } else {
    message->clear();
  }
  rd_kafka_message_destroy(record);
  return true;
}

void KafkaClient::commit() { rd_kafka_commit(impl_->consumer, nullptr, 0); }

bool KafkaClient::produce(const std::string& topic, const std::string& key,
                          const std::string& value) {
  rd_kafka_resp_err_t result = rd_kafka_producev(
      impl_->producer, RD_KAFKA_V_TOPIC(topic.c_str()),
      RD_KAFKA_V_KEY(const_cast<char*>(key.data()), key.size()),
      RD_KAFKA_V_VALUE(const_cast<char*>(value.data()), value.size()), RD_KAFKA_V_END);
  if (result != RD_KAFKA_RESP_ERR_NO_ERROR) {
    return false;
  }
  // Flush so delivery is confirmed before the offset is committed.
  rd_kafka_flush(impl_->producer, 5000);
  return true;
}

}  // namespace rghw
