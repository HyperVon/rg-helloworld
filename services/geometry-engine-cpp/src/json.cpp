#include "geometry_engine/json.hpp"

#include <charconv>
#include <cmath>
#include <cstdint>
#include <iomanip>
#include <sstream>

namespace rghw {

bool Json::asBool() const {
  if (type_ != Type::Bool) {
    throw JsonError("not a boolean");
  }
  return bool_;
}

double Json::asNumber() const {
  if (type_ != Type::Number) {
    throw JsonError("not a number");
  }
  return number_;
}

int64_t Json::asInt64() const {
  if (type_ != Type::Number) {
    throw JsonError("not a number");
  }
  return static_cast<int64_t>(number_);
}

const std::string& Json::asString() const {
  if (type_ != Type::String) {
    throw JsonError("not a string");
  }
  return string_;
}

const Json& Json::at(const std::string& key) const {
  static const Json kMissing = Json::null();
  auto it = object_.find(key);
  if (it == object_.end()) {
    return kMissing;
  }
  return it->second;
}

namespace {

class Parser {
 public:
  explicit Parser(const std::string& text) : text_(text) {}

  Json parseValue() {
    skipWhitespace();
    if (pos_ >= text_.size()) {
      fail("unexpected end of input");
    }
    switch (text_[pos_]) {
      case '{':
        return parseObject();
      case '[':
        return parseArray();
      case '"':
        return Json::str(parseString());
      case 't':
        expectLiteral("true");
        return Json::boolean(true);
      case 'f':
        expectLiteral("false");
        return Json::boolean(false);
      case 'n':
        expectLiteral("null");
        return Json::null();
      default:
        return parseNumber();
    }
  }

  bool finished() {
    skipWhitespace();
    return pos_ >= text_.size();
  }

 private:
  const std::string& text_;
  size_t pos_ = 0;

  [[noreturn]] void fail(const std::string& message) const {
    throw JsonError("JSON parse error at offset " + std::to_string(pos_) + ": " + message);
  }

  void skipWhitespace() {
    while (pos_ < text_.size() && (text_[pos_] == ' ' || text_[pos_] == '\t' ||
                                   text_[pos_] == '\n' || text_[pos_] == '\r')) {
      ++pos_;
    }
  }

  void expectLiteral(const char* literal) {
    const size_t len = std::char_traits<char>::length(literal);
    if (text_.compare(pos_, len, literal) != 0) {
      fail("expected literal");
    }
    pos_ += len;
  }

  Json parseObject() {
    ++pos_;  // consume '{'
    Json result = Json::object();
    skipWhitespace();
    if (pos_ < text_.size() && text_[pos_] == '}') {
      ++pos_;
      return result;
    }
    while (true) {
      skipWhitespace();
      if (pos_ >= text_.size() || text_[pos_] != '"') {
        fail("expected object key");
      }
      std::string key = parseString();
      skipWhitespace();
      if (pos_ >= text_.size() || text_[pos_] != ':') {
        fail("expected ':'");
      }
      ++pos_;
      result.objectItems()[std::move(key)] = parseValue();
      skipWhitespace();
      if (pos_ >= text_.size()) {
        fail("unterminated object");
      }
      if (text_[pos_] == ',') {
        ++pos_;
        continue;
      }
      if (text_[pos_] == '}') {
        ++pos_;
        return result;
      }
      fail("expected ',' or '}'");
    }
  }

  Json parseArray() {
    ++pos_;  // consume '['
    Json result = Json::array();
    skipWhitespace();
    if (pos_ < text_.size() && text_[pos_] == ']') {
      ++pos_;
      return result;
    }
    while (true) {
      result.arrayItems().push_back(parseValue());
      skipWhitespace();
      if (pos_ >= text_.size()) {
        fail("unterminated array");
      }
      if (text_[pos_] == ',') {
        ++pos_;
        continue;
      }
      if (text_[pos_] == ']') {
        ++pos_;
        return result;
      }
      fail("expected ',' or ']'");
    }
  }

  std::string parseString() {
    if (pos_ >= text_.size() || text_[pos_] != '"') {
      fail("expected string");
    }
    ++pos_;
    std::string out;
    while (true) {
      if (pos_ >= text_.size()) {
        fail("unterminated string");
      }
      char c = text_[pos_++];
      if (c == '"') {
        return out;
      }
      if (c == '\\') {
        if (pos_ >= text_.size()) {
          fail("unterminated escape");
        }
        char escape = text_[pos_++];
        switch (escape) {
          case '"':
            out.push_back('"');
            break;
          case '\\':
            out.push_back('\\');
            break;
          case '/':
            out.push_back('/');
            break;
          case 'b':
            out.push_back('\b');
            break;
          case 'f':
            out.push_back('\f');
            break;
          case 'n':
            out.push_back('\n');
            break;
          case 'r':
            out.push_back('\r');
            break;
          case 't':
            out.push_back('\t');
            break;
          case 'u': {
            if (pos_ + 4 > text_.size()) {
              fail("short unicode escape");
            }
            unsigned int code = 0;
            for (int i = 0; i < 4; ++i) {
              code = (code << 4) | hexDigit(text_[pos_++]);
            }
            appendUtf8(out, code);
            break;
          }
          default:
            fail("invalid escape");
        }
      } else {
        out.push_back(c);
      }
    }
  }

  static unsigned int hexDigit(char c) {
    if (c >= '0' && c <= '9') {
      return static_cast<unsigned int>(c - '0');
    }
    if (c >= 'a' && c <= 'f') {
      return static_cast<unsigned int>(c - 'a' + 10);
    }
    if (c >= 'A' && c <= 'F') {
      return static_cast<unsigned int>(c - 'A' + 10);
    }
    throw JsonError("invalid hex digit in unicode escape");
  }

  static void appendUtf8(std::string& out, unsigned int code) {
    if (code < 0x80) {
      out.push_back(static_cast<char>(code));
    } else if (code < 0x800) {
      out.push_back(static_cast<char>(0xC0 | (code >> 6)));
      out.push_back(static_cast<char>(0x80 | (code & 0x3F)));
    } else {
      out.push_back(static_cast<char>(0xE0 | (code >> 12)));
      out.push_back(static_cast<char>(0x80 | ((code >> 6) & 0x3F)));
      out.push_back(static_cast<char>(0x80 | (code & 0x3F)));
    }
  }

  Json parseNumber() {
    size_t start = pos_;
    if (pos_ < text_.size() && (text_[pos_] == '-' || text_[pos_] == '+')) {
      ++pos_;
    }
    while (pos_ < text_.size() &&
           ((text_[pos_] >= '0' && text_[pos_] <= '9') || text_[pos_] == '.' ||
            text_[pos_] == 'e' || text_[pos_] == 'E' || text_[pos_] == '-' || text_[pos_] == '+')) {
      ++pos_;
    }
    if (pos_ == start) {
      fail("invalid value");
    }
    std::string token = text_.substr(start, pos_ - start);
    double value = 0.0;
    auto result = std::from_chars(token.data(), token.data() + token.size(), value);
    if (result.ec != std::errc()) {
      fail("invalid number");
    }
    return Json::number(value);
  }
};

void escapeString(const std::string& value, std::string& out) {
  out.push_back('"');
  for (char c : value) {
    switch (c) {
      case '"':
        out += "\\\"";
        break;
      case '\\':
        out += "\\\\";
        break;
      case '\b':
        out += "\\b";
        break;
      case '\f':
        out += "\\f";
        break;
      case '\n':
        out += "\\n";
        break;
      case '\r':
        out += "\\r";
        break;
      case '\t':
        out += "\\t";
        break;
      default:
        if (static_cast<unsigned char>(c) < 0x20) {
          char buffer[8];
          std::snprintf(buffer, sizeof(buffer), "\\u%04x", static_cast<unsigned char>(c));
          out += buffer;
        } else {
          out.push_back(c);
        }
    }
  }
  out.push_back('"');
}

void formatNumber(double value, std::string& out) {
  if (std::isnan(value)) {
    throw JsonError("cannot serialize NaN");
  }
  if (std::isinf(value)) {
    throw JsonError("cannot serialize infinity");
  }
  if (value == static_cast<int64_t>(value) && std::fabs(value) < 9.0e15) {
    out += std::to_string(static_cast<int64_t>(value));
    return;
  }
  char buffer[32];
  auto result = std::to_chars(buffer, buffer + sizeof(buffer), value);
  if (result.ec != std::errc()) {
    throw JsonError("cannot format number");
  }
  out.append(buffer, result.ptr);
}

void serializeValue(const Json& value, std::string& out) {
  switch (value.type()) {
    case Json::Type::Null:
      out += "null";
      break;
    case Json::Type::Bool:
      out += value.asBool() ? "true" : "false";
      break;
    case Json::Type::Number:
      formatNumber(value.asNumber(), out);
      break;
    case Json::Type::String:
      escapeString(value.asString(), out);
      break;
    case Json::Type::Array: {
      out.push_back('[');
      bool first = true;
      for (const Json& item : value.arrayItems()) {
        if (!first) {
          out.push_back(',');
        }
        first = false;
        serializeValue(item, out);
      }
      out.push_back(']');
      break;
    }
    case Json::Type::Object: {
      out.push_back('{');
      bool first = true;
      for (const auto& [key, item] : value.objectItems()) {
        if (!first) {
          out.push_back(',');
        }
        first = false;
        escapeString(key, out);
        out.push_back(':');
        serializeValue(item, out);
      }
      out.push_back('}');
      break;
    }
  }
}

void prettyValue(const Json& value, int indent, std::string& out) {
  switch (value.type()) {
    case Json::Type::Array: {
      if (value.arrayItems().empty()) {
        out += "[]";
        return;
      }
      out += "[\n";
      for (const Json& item : value.arrayItems()) {
        out.append(indent + 2, ' ');
        prettyValue(item, indent + 2, out);
        out += ",\n";
      }
      out.pop_back();
      out += "\n";
      out.append(indent, ' ');
      out.push_back(']');
      break;
    }
    case Json::Type::Object: {
      if (value.objectItems().empty()) {
        out += "{}";
        return;
      }
      out += "{\n";
      for (const auto& [key, item] : value.objectItems()) {
        out.append(indent + 2, ' ');
        escapeString(key, out);
        out += ": ";
        prettyValue(item, indent + 2, out);
        out += ",\n";
      }
      out.pop_back();
      out += "\n";
      out.append(indent, ' ');
      out.push_back('}');
      break;
    }
    default:
      serializeValue(value, out);
  }
}

}  // namespace

Json Json::parse(const std::string& text) {
  Parser parser(text);
  Json value = parser.parseValue();
  if (!parser.finished()) {
    throw JsonError("JSON parse error: trailing content after value");
  }
  return value;
}

std::string Json::serialize() const {
  std::string out;
  serializeValue(*this, out);
  return out;
}

std::string Json::pretty(int indent) const {
  std::string out;
  prettyValue(*this, indent, out);
  return out;
}

}  // namespace rghw
