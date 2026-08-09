#include <iostream>
#include <limits>
#include <string>

#include "geometry_engine/json.hpp"

namespace {

int failures = 0;

void expect(bool condition, const std::string& message) {
  if (!condition) {
    std::cerr << "FAIL: " << message << '\n';
    ++failures;
  }
}

void expectEq(const std::string& actual, const std::string& expected, const std::string& message) {
  if (actual != expected) {
    std::cerr << "FAIL: " << message << "\n  expected: " << expected << "\n  actual:   " << actual
              << '\n';
    ++failures;
  }
}

void expectThrows(const std::string& text) {
  try {
    rghw::Json::parse(text);
    std::cerr << "FAIL: expected parse error for: " << text << '\n';
    ++failures;
  } catch (const rghw::JsonError&) {
  }
}

}  // namespace

int main() {
  // Round trip of a nested document.
  rghw::Json doc = rghw::Json::object();
  doc.objectItems()["name"] = rghw::Json::str("H");
  doc.objectItems()["count"] = rghw::Json::number(11.0);
  doc.objectItems()["ratio"] = rghw::Json::number(0.5);
  doc.objectItems()["enabled"] = rghw::Json::boolean(true);
  doc.objectItems()["missing"] = rghw::Json::null();
  rghw::Json items = rghw::Json::array();
  items.arrayItems().push_back(rghw::Json::number(1.0));
  items.arrayItems().push_back(rghw::Json::str("two"));
  doc.objectItems()["items"] = items;

  std::string serialized = doc.serialize();
  expectEq(serialized,
           "{\"count\":11,\"enabled\":true,\"items\":[1,\"two\"],\"missing\":null,\"name\":\"H\","
           "\"ratio\":0.5}",
           "canonical serialization with sorted keys");

  rghw::Json reparsed = rghw::Json::parse(serialized);
  expectEq(reparsed.serialize(), serialized, "parse round trip");
  expect(reparsed.at("name").isString() && reparsed.at("name").asString() == "H", "string value");
  expect(reparsed.at("count").asInt64() == 11, "integer value");
  expect(reparsed.at("ratio").asNumber() == 0.5, "fractional value");
  expect(reparsed.at("enabled").asBool(), "boolean value");
  expect(reparsed.at("missing").isNull(), "null value");
  expect(reparsed.at("absent").isNull(), "missing key reads as null");
  expect(reparsed.at("items").arrayItems().size() == 2, "array size");

  // Key ordering is canonical regardless of input order.
  std::string reordered = "{\"z\":1,\"a\":{\"y\":2,\"b\":3},\"m\":[1,2]}";
  expectEq(rghw::Json::parse(reordered).serialize(),
           "{\"a\":{\"b\":3,\"y\":2},\"m\":[1,2],\"z\":1}", "nested canonical ordering");

  // String escaping round trip.
  rghw::Json escaped = rghw::Json::str("a\"b\\c\nd\te\u0001f");
  rghw::Json escapedBack = rghw::Json::parse(escaped.serialize());
  expectEq(escapedBack.asString(), "a\"b\\c\nd\te\u0001f", "escape round trip");

  // Unicode escape parsing.
  rghw::Json unicode = rghw::Json::parse("\"\\u0041\\u00e9\"");
  expectEq(unicode.asString(), "A\u00e9", "unicode escapes");

  // Negative and exponent numbers.
  expectEq(rghw::Json::parse("-2.5").serialize(), "-2.5", "negative number");
  expectEq(rghw::Json::parse("1e3").serialize(), "1000", "exponent number");

  // Empty containers.
  expectEq(rghw::Json::parse("[]").serialize(), "[]", "empty array");
  expectEq(rghw::Json::parse("{}").serialize(), "{}", "empty object");

  // Malformed input.
  expectThrows("{");
  expectThrows("[1,]");
  expectThrows("{\"a\":}");
  expectThrows("{\"a\" 1}");
  expectThrows("nul");
  expectThrows("{\"a\":1} trailing");
  expectThrows("\"unterminated");
  expectThrows("{\"a\":\"\\x\"}");

  // Serialization errors: NaN must not serialize.
  rghw::Json nan = rghw::Json::number(0.0);
  nan.objectItems()["x"] = rghw::Json::number(0.0 / 0.0);
  nan = rghw::Json::object();
  nan.objectItems()["x"] = rghw::Json::number(0.0 / 0.0);
  try {
    nan.serialize();
    std::cerr << "FAIL: expected NaN serialization error\n";
    ++failures;
  } catch (const rghw::JsonError&) {
  }

  // Pretty output.
  std::string pretty = doc.pretty();
  expect(pretty.find('\n') != std::string::npos, "pretty output is multiline");

  // Parsing the boolean literal `false` exercises the false branch.
  expect(rghw::Json::parse("false").asBool() == false, "false literal");

  // Type-mismatch accessors throw on the null sentinel returned by at().
  const rghw::Json& absent = doc.at("absent");
  try {
    absent.asBool();
    std::cerr << "FAIL: expected type error reading null as bool\n";
    ++failures;
  } catch (const rghw::JsonError&) {
  }
  try {
    absent.asNumber();
    std::cerr << "FAIL: expected type error reading null as number\n";
    ++failures;
  } catch (const rghw::JsonError&) {
  }
  try {
    absent.asString();
    std::cerr << "FAIL: expected type error reading null as string\n";
    ++failures;
  } catch (const rghw::JsonError&) {
  }
  try {
    absent.asInt64();
    std::cerr << "FAIL: expected type error reading null as int64\n";
    ++failures;
  } catch (const rghw::JsonError&) {
  }

  // Empty input.
  expectThrows("");

  // Object/array structural errors.
  expectThrows("{1");
  expectThrows("{\"a\":1 \"b\":2}");
  expectThrows("{\"a\":1");
  expectThrows("[1");
  expectThrows("[1 2]");
  expectThrows("z");
  expectThrows("+");
  expectThrows("\"\\");
  expectThrows("\"\\u123");
  expectThrows("\"\\u00GG");

  // Escaped control characters and solidus round trip through parse.
  expectEq(rghw::Json::parse("\"\\b\\f\\r\\/\"").asString(), "\b\f\r/",
           "escape parse of \\b \\f \\r \\/");

  // Upper-case hex digits and multi-byte UTF-8 in unicode escapes.
  expectEq(rghw::Json::parse("\"\\u00FF\"").asString(), "\u00FF", "uppercase hex");
  expectEq(rghw::Json::parse("\"\\u0800\"").asString(), "\u0800", "three-byte utf8");

  // Pretty printing of empty containers.
  expectEq(rghw::Json::parse("[]").pretty(), "[]", "pretty empty array");
  expectEq(rghw::Json::parse("{}").pretty(), "{}", "pretty empty object");

  // Serializing control characters escapes them.
  expectEq(rghw::Json::str("\b\f\r").serialize(), "\"\\b\\f\\r\"", "serialize escapes");

  // Infinity must not serialize.
  rghw::Json inf = rghw::Json::object();
  inf.objectItems()["x"] = rghw::Json::number(std::numeric_limits<double>::infinity());
  try {
    inf.serialize();
    std::cerr << "FAIL: expected infinity serialization error\n";
    ++failures;
  } catch (const rghw::JsonError&) {
  }

  // Type accessor errors.
  try {
    doc.at("name").asNumber();
    std::cerr << "FAIL: expected type error reading string as number\n";
    ++failures;
  } catch (const rghw::JsonError&) {
  }

  if (failures == 0) {
    std::cout << "json tests passed\n";
    return 0;
  }
  std::cerr << failures << " json test(s) failed\n";
  return 1;
}
