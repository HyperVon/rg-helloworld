#ifndef RGHELLO_GEOMETRY_ENGINE_JSON_HPP_
#define RGHELLO_GEOMETRY_ENGINE_JSON_HPP_

#include <cstddef>
#include <map>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>
namespace rghello {

class JsonError : public std::runtime_error {
 public:
  explicit JsonError(const std::string& message) : std::runtime_error(message) {}
};

// Minimal deterministic JSON value. Objects are stored in std::map so
// serialization always emits keys in sorted order; this makes the JSON
// byte-for-byte canonical for hashing and artifact lineage.
class Json {
 public:
  enum class Type { Null, Bool, Number, String, Array, Object };

  Json() : type_(Type::Null) {}
  static Json null() { return Json(); }
  static Json boolean(bool value) {
    Json j;
    j.type_ = Type::Bool;
    j.bool_ = value;
    return j;
  }
  static Json number(double value) {
    Json j;
    j.type_ = Type::Number;
    j.number_ = value;
    return j;
  }
  static Json str(std::string value) {
    Json j;
    j.type_ = Type::String;
    j.string_ = std::move(value);
    return j;
  }
  static Json array() {
    Json j;
    j.type_ = Type::Array;
    return j;
  }
  static Json object() {
    Json j;
    j.type_ = Type::Object;
    return j;
  }

  Type type() const { return type_; }
  bool isNull() const { return type_ == Type::Null; }
  bool isBool() const { return type_ == Type::Bool; }
  bool isNumber() const { return type_ == Type::Number; }
  bool isString() const { return type_ == Type::String; }
  bool isArray() const { return type_ == Type::Array; }
  bool isObject() const { return type_ == Type::Object; }

  bool asBool() const;
  double asNumber() const;
  int64_t asInt64() const;
  const std::string& asString() const;
  std::vector<Json>& arrayItems() { return array_; }
  const std::vector<Json>& arrayItems() const { return array_; }
  std::map<std::string, Json>& objectItems() { return object_; }
  const std::map<std::string, Json>& objectItems() const { return object_; }

  // Returns the value for key, or null Json when absent.
  const Json& at(const std::string& key) const;
  bool has(const std::string& key) const { return object_.count(key) != 0; }

  // Parses text into a Json value. Throws JsonError on malformed input.
  static Json parse(const std::string& text);

  // Compact canonical serialization: object keys sorted, numbers via
  // shortest round-trip formatting, strings JSON-escaped.
  std::string serialize() const;

  // Serializes with indentation for human-readable artifacts.
  std::string pretty(int indent = 2) const;

 private:
  Type type_;
  bool bool_ = false;
  double number_ = 0.0;
  std::string string_;
  std::vector<Json> array_;
  std::map<std::string, Json> object_;
};

}  // namespace rghello

#endif  // RGHELLO_GEOMETRY_ENGINE_JSON_HPP_
