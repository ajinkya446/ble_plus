#include <flutter/method_call.h>
#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>
#include <gtest/gtest.h>
#include <windows.h>

#include <memory>
#include <optional>
#include <string>
#include <variant>

#include "ble_plus_plugin.h"

namespace ble_plus {
namespace test {

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;
using flutter::MethodCall;
using flutter::MethodResultFunctions;

}  // namespace

// An unknown method must respond NotImplemented (the BLE plugin does not
// handle "getPlatformVersion", the method of the original flutter create
// template).
TEST(BlePlusPlugin, UnknownMethodReturnsNotImplemented) {
  BlePlusPlugin plugin;
  bool not_implemented = false;
  plugin.HandleMethodCall(
      MethodCall("noSuchMethod", std::make_unique<EncodableValue>()),
      std::make_unique<MethodResultFunctions<>>(
          /*success*/ nullptr,
          /*error*/ nullptr,
          /*notImplemented*/ [&not_implemented]() { not_implemented = true; }));
  EXPECT_TRUE(not_implemented);
}

// getBondState of a never-connected device must respond 0 (none) synchronously,
// without errors or inconsistent state.
TEST(BlePlusPlugin, GetBondStateUnknownDeviceReturnsNone) {
  BlePlusPlugin plugin;
  std::optional<int32_t> value;
  EncodableMap args;
  args[EncodableValue("deviceId")] = EncodableValue("AA:BB:CC:DD:EE:FF");
  plugin.HandleMethodCall(
      MethodCall("getBondState", std::make_unique<EncodableValue>(args)),
      std::make_unique<MethodResultFunctions<>>(
          [&value](const EncodableValue* result) {
            value = std::get<int32_t>(*result);
          },
          /*error*/ nullptr,
          /*notImplemented*/ nullptr));
  ASSERT_TRUE(value.has_value());
  EXPECT_EQ(*value, 0);
}

}  // namespace test
}  // namespace ble_plus
