#include "include/ble_plus/ble_plus_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>
#include <gio/gio.h>
#include <sys/utsname.h>

#include <cstring>
#include <map>
#include <string>
#include <vector>

#include "ble_plus_plugin_private.h"

#define BLE_PLUS_PLUGIN(obj) \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), ble_plus_plugin_get_type(), \
                              BlePlusPlugin))

struct _BlePlusPlugin {
  GObject parent_instance;
  FlMethodChannel* method_channel;
  FlEventChannel* scan_channel;
  FlEventChannel* connection_channel;
  FlEventChannel* characteristic_channel;
  GDBusConnection* system_bus;
  GDBusProxy* adapter_proxy;
  guint interfaces_added_signal;
  guint properties_changed_signal;
  FlEventSink* scan_sink;
  FlEventSink* connection_sink;
  FlEventSink* characteristic_sink;
};

G_DEFINE_TYPE(BlePlusPlugin, ble_plus_plugin, g_object_get_type())

// ═══════════════════════════════════════════════════════════
// HELPERS
// ═══════════════════════════════════════════════════════════

static GDBusConnection* ensure_system_bus(BlePlusPlugin* self) {
  if (self->system_bus == nullptr) {
    GError* error = nullptr;
    self->system_bus = g_bus_get_sync(G_BUS_TYPE_SYSTEM, nullptr, &error);
    if (error) {
      g_warning("Failed to connect to system bus: %s", error->message);
      g_error_free(error);
    }
  }
  return self->system_bus;
}

static GDBusProxy* ensure_adapter(BlePlusPlugin* self) {
  if (self->adapter_proxy != nullptr) return self->adapter_proxy;

  GDBusConnection* bus = ensure_system_bus(self);
  if (bus == nullptr) return nullptr;

  GError* error = nullptr;
  self->adapter_proxy = g_dbus_proxy_new_sync(
      bus, G_DBUS_PROXY_FLAGS_NONE, nullptr,
      "org.bluez", "/org/bluez/hci0", "org.bluez.Adapter1",
      nullptr, &error);
  if (error) {
    g_warning("Failed to get adapter proxy: %s", error->message);
    g_error_free(error);
  }
  return self->adapter_proxy;
}

// ═══════════════════════════════════════════════════════════
// SCAN HANDLING
// ═══════════════════════════════════════════════════════════

static void on_interfaces_added(GDBusConnection* connection,
                                 const gchar* sender_name,
                                 const gchar* object_path,
                                 const gchar* interface_name,
                                 const gchar* signal_name,
                                 GVariant* parameters,
                                 gpointer user_data) {
  BlePlusPlugin* self = BLE_PLUS_PLUGIN(user_data);
  if (self->scan_sink == nullptr) return;

  GVariant* interfaces_and_properties;
  const gchar* path;
  g_variant_get(parameters, "(&o@a{sa{sv}})", &path, &interfaces_and_properties);

  GVariantIter iter;
  const gchar* iface_name;
  GVariant* properties;
  g_variant_iter_init(&iter, interfaces_and_properties);
  while (g_variant_iter_next(&iter, "{&s@a{sv}}", &iface_name, &properties)) {
    if (g_strcmp0(iface_name, "org.bluez.Device1") == 0) {
      g_autoptr(FlValue) result = fl_value_new_map();

      GVariant* addr_var = g_variant_lookup_value(properties, "Address", G_VARIANT_TYPE_STRING);
      GVariant* name_var = g_variant_lookup_value(properties, "Name", G_VARIANT_TYPE_STRING);
      GVariant* rssi_var = g_variant_lookup_value(properties, "RSSI", G_VARIANT_TYPE_INT16);

      if (addr_var) {
        fl_value_set_string_take(result, "deviceId",
            fl_value_new_string(g_variant_get_string(addr_var, nullptr)));
        g_variant_unref(addr_var);
      }
      if (name_var) {
        fl_value_set_string_take(result, "name",
            fl_value_new_string(g_variant_get_string(name_var, nullptr)));
        g_variant_unref(name_var);
      } else {
        fl_value_set_string_take(result, "name", fl_value_new_null());
      }
      fl_value_set_string_take(result, "rssi",
          fl_value_new_int(rssi_var ? g_variant_get_int16(rssi_var) : -100));
      if (rssi_var) g_variant_unref(rssi_var);

      fl_value_set_string_take(result, "timestampMs",
          fl_value_new_int(g_get_real_time() / 1000));
      fl_value_set_string_take(result, "connectable", fl_value_new_bool(TRUE));
      fl_value_set_string_take(result, "serviceUuids", fl_value_new_list());
      fl_value_set_string_take(result, "manufacturerData", fl_value_new_map());
      fl_value_set_string_take(result, "serviceData", fl_value_new_map());

      // Send to Flutter
      fl_event_sink_success(self->scan_sink, result, nullptr);
    }
    g_variant_unref(properties);
  }
  g_variant_unref(interfaces_and_properties);
}

// ═══════════════════════════════════════════════════════════
// METHOD CALL HANDLER
// ═══════════════════════════════════════════════════════════

static void ble_plus_plugin_handle_method_call(
    BlePlusPlugin* self,
    FlMethodCall* method_call) {
  g_autoptr(FlMethodResponse) response = nullptr;
  const gchar* method = fl_method_call_get_name(method_call);

  if (strcmp(method, "getAdapterState") == 0) {
    GDBusProxy* adapter = ensure_adapter(self);
    if (adapter) {
      GVariant* powered = g_dbus_proxy_get_cached_property(adapter, "Powered");
      if (powered && g_variant_get_boolean(powered)) {
        g_autoptr(FlValue) val = fl_value_new_int(4); // poweredOn
        response = FL_METHOD_RESPONSE(fl_method_success_response_new(val));
      } else {
        g_autoptr(FlValue) val = fl_value_new_int(6); // poweredOff
        response = FL_METHOD_RESPONSE(fl_method_success_response_new(val));
      }
      if (powered) g_variant_unref(powered);
    } else {
      g_autoptr(FlValue) val = fl_value_new_int(1); // unsupported
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(val));
    }
  } else if (strcmp(method, "startScan") == 0) {
    GDBusProxy* adapter = ensure_adapter(self);
    if (adapter) {
      GDBusConnection* bus = ensure_system_bus(self);
      // Subscribe to InterfacesAdded for new devices
      self->interfaces_added_signal = g_dbus_connection_signal_subscribe(
          bus, "org.bluez", "org.freedesktop.DBus.ObjectManager",
          "InterfacesAdded", nullptr, nullptr,
          G_DBUS_SIGNAL_FLAGS_NONE, on_interfaces_added, self, nullptr);

      GError* error = nullptr;
      g_dbus_proxy_call_sync(adapter, "StartDiscovery", nullptr,
                              G_DBUS_CALL_FLAGS_NONE, -1, nullptr, &error);
      if (error) {
        g_warning("StartDiscovery failed: %s", error->message);
        g_error_free(error);
      }
    }
    g_autoptr(FlValue) val = fl_value_new_null();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(val));
  } else if (strcmp(method, "stopScan") == 0) {
    GDBusProxy* adapter = ensure_adapter(self);
    if (adapter) {
      GError* error = nullptr;
      g_dbus_proxy_call_sync(adapter, "StopDiscovery", nullptr,
                              G_DBUS_CALL_FLAGS_NONE, -1, nullptr, &error);
      if (error) g_error_free(error);

      if (self->interfaces_added_signal > 0) {
        g_dbus_connection_signal_unsubscribe(self->system_bus,
                                              self->interfaces_added_signal);
        self->interfaces_added_signal = 0;
      }
    }
    g_autoptr(FlValue) val = fl_value_new_null();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(val));
  } else if (strcmp(method, "connect") == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
    FlValue* device_id_val = fl_value_lookup_string(args, "deviceId");
    if (device_id_val) {
      // BlueZ connect via Device1 proxy
      const gchar* device_id = fl_value_get_string(device_id_val);
      // Convert address to path: XX:XX:XX:XX:XX:XX -> /org/bluez/hci0/dev_XX_XX_XX_XX_XX_XX
      g_autofree gchar* path_addr = g_strdup(device_id);
      for (gchar* p = path_addr; *p; p++) {
        if (*p == ':') *p = '_';
      }
      g_autofree gchar* obj_path = g_strdup_printf("/org/bluez/hci0/dev_%s", path_addr);

      GDBusConnection* bus = ensure_system_bus(self);
      GError* error = nullptr;
      GDBusProxy* device_proxy = g_dbus_proxy_new_sync(
          bus, G_DBUS_PROXY_FLAGS_NONE, nullptr,
          "org.bluez", obj_path, "org.bluez.Device1",
          nullptr, &error);

      if (device_proxy) {
        g_dbus_proxy_call_sync(device_proxy, "Connect", nullptr,
                                G_DBUS_CALL_FLAGS_NONE, 30000, nullptr, &error);
        if (error) {
          if (self->connection_sink) {
            g_autoptr(FlValue) event = fl_value_new_map();
            fl_value_set_string_take(event, "deviceId", fl_value_new_string(device_id));
            fl_value_set_string_take(event, "state", fl_value_new_int(0));
            fl_value_set_string_take(event, "errorMessage", fl_value_new_string(error->message));
            fl_event_sink_success(self->connection_sink, event, nullptr);
          }
          g_error_free(error);
        } else {
          if (self->connection_sink) {
            g_autoptr(FlValue) event = fl_value_new_map();
            fl_value_set_string_take(event, "deviceId", fl_value_new_string(device_id));
            fl_value_set_string_take(event, "state", fl_value_new_int(2));
            fl_event_sink_success(self->connection_sink, event, nullptr);
          }
        }
        g_object_unref(device_proxy);
      } else {
        if (error) g_error_free(error);
      }
    }
    g_autoptr(FlValue) val = fl_value_new_null();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(val));
  } else if (strcmp(method, "disconnect") == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
    FlValue* device_id_val = fl_value_lookup_string(args, "deviceId");
    if (device_id_val) {
      const gchar* device_id = fl_value_get_string(device_id_val);
      g_autofree gchar* path_addr = g_strdup(device_id);
      for (gchar* p = path_addr; *p; p++) { if (*p == ':') *p = '_'; }
      g_autofree gchar* obj_path = g_strdup_printf("/org/bluez/hci0/dev_%s", path_addr);

      GDBusConnection* bus = ensure_system_bus(self);
      GError* error = nullptr;
      GDBusProxy* device_proxy = g_dbus_proxy_new_sync(
          bus, G_DBUS_PROXY_FLAGS_NONE, nullptr,
          "org.bluez", obj_path, "org.bluez.Device1",
          nullptr, &error);
      if (device_proxy) {
        g_dbus_proxy_call_sync(device_proxy, "Disconnect", nullptr,
                                G_DBUS_CALL_FLAGS_NONE, -1, nullptr, nullptr);
        g_object_unref(device_proxy);
      }
      if (error) g_error_free(error);

      if (self->connection_sink) {
        g_autoptr(FlValue) event = fl_value_new_map();
        fl_value_set_string_take(event, "deviceId", fl_value_new_string(device_id));
        fl_value_set_string_take(event, "state", fl_value_new_int(0));
        fl_event_sink_success(self->connection_sink, event, nullptr);
      }
    }
    g_autoptr(FlValue) val = fl_value_new_null();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(val));
  } else if (strcmp(method, "createBond") == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
    FlValue* device_id_val = fl_value_lookup_string(args, "deviceId");
    if (device_id_val) {
      const gchar* device_id = fl_value_get_string(device_id_val);
      g_autofree gchar* path_addr = g_strdup(device_id);
      for (gchar* p = path_addr; *p; p++) { if (*p == ':') *p = '_'; }
      g_autofree gchar* obj_path = g_strdup_printf("/org/bluez/hci0/dev_%s", path_addr);

      GDBusConnection* bus = ensure_system_bus(self);
      GError* error = nullptr;
      GDBusProxy* device_proxy = g_dbus_proxy_new_sync(
          bus, G_DBUS_PROXY_FLAGS_NONE, nullptr,
          "org.bluez", obj_path, "org.bluez.Device1",
          nullptr, &error);
      if (device_proxy) {
        g_dbus_proxy_call_sync(device_proxy, "Pair", nullptr,
                                G_DBUS_CALL_FLAGS_NONE, 30000, nullptr, &error);
        g_object_unref(device_proxy);
      }
      if (error) g_error_free(error);
    }
    g_autoptr(FlValue) val = fl_value_new_null();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(val));
  } else if (strcmp(method, "removeBond") == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
    FlValue* device_id_val = fl_value_lookup_string(args, "deviceId");
    if (device_id_val) {
      const gchar* device_id = fl_value_get_string(device_id_val);
      g_autofree gchar* path_addr = g_strdup(device_id);
      for (gchar* p = path_addr; *p; p++) { if (*p == ':') *p = '_'; }
      g_autofree gchar* obj_path = g_strdup_printf("/org/bluez/hci0/dev_%s", path_addr);

      GDBusProxy* adapter = ensure_adapter(self);
      if (adapter) {
        GError* error = nullptr;
        g_dbus_proxy_call_sync(adapter, "RemoveDevice",
            g_variant_new("(o)", obj_path),
            G_DBUS_CALL_FLAGS_NONE, -1, nullptr, &error);
        if (error) g_error_free(error);
      }
    }
    g_autoptr(FlValue) val = fl_value_new_null();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(val));
  } else if (strcmp(method, "getBondState") == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
    FlValue* device_id_val = fl_value_lookup_string(args, "deviceId");
    int bond_state = 0;
    if (device_id_val) {
      const gchar* device_id = fl_value_get_string(device_id_val);
      g_autofree gchar* path_addr = g_strdup(device_id);
      for (gchar* p = path_addr; *p; p++) { if (*p == ':') *p = '_'; }
      g_autofree gchar* obj_path = g_strdup_printf("/org/bluez/hci0/dev_%s", path_addr);

      GDBusConnection* bus = ensure_system_bus(self);
      GError* error = nullptr;
      GDBusProxy* device_proxy = g_dbus_proxy_new_sync(
          bus, G_DBUS_PROXY_FLAGS_NONE, nullptr,
          "org.bluez", obj_path, "org.bluez.Device1",
          nullptr, &error);
      if (device_proxy) {
        GVariant* paired = g_dbus_proxy_get_cached_property(device_proxy, "Paired");
        if (paired && g_variant_get_boolean(paired)) {
          bond_state = 2; // bonded
        }
        if (paired) g_variant_unref(paired);
        g_object_unref(device_proxy);
      }
      if (error) g_error_free(error);
    }
    g_autoptr(FlValue) val = fl_value_new_int(bond_state);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(val));
  } else if (strcmp(method, "getPlatformVersion") == 0) {
    response = get_platform_version();
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(method_call, response, nullptr);
}

FlMethodResponse* get_platform_version() {
  struct utsname uname_data = {};
  uname(&uname_data);
  g_autofree gchar *version = g_strdup_printf("Linux %s", uname_data.version);
  g_autoptr(FlValue) result = fl_value_new_string(version);
  return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

static void ble_plus_plugin_dispose(GObject* object) {
  BlePlusPlugin* self = BLE_PLUS_PLUGIN(object);
  if (self->system_bus && self->interfaces_added_signal > 0) {
    g_dbus_connection_signal_unsubscribe(self->system_bus,
                                          self->interfaces_added_signal);
  }
  if (self->adapter_proxy) g_object_unref(self->adapter_proxy);
  if (self->system_bus) g_object_unref(self->system_bus);
  G_OBJECT_CLASS(ble_plus_plugin_parent_class)->dispose(object);
}

static void ble_plus_plugin_class_init(BlePlusPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = ble_plus_plugin_dispose;
}

static void ble_plus_plugin_init(BlePlusPlugin* self) {
  self->system_bus = nullptr;
  self->adapter_proxy = nullptr;
  self->interfaces_added_signal = 0;
  self->scan_sink = nullptr;
  self->connection_sink = nullptr;
  self->characteristic_sink = nullptr;
}

static void method_call_cb(FlMethodChannel* channel, FlMethodCall* method_call,
                           gpointer user_data) {
  BlePlusPlugin* plugin = BLE_PLUS_PLUGIN(user_data);
  ble_plus_plugin_handle_method_call(plugin, method_call);
}

// Event channel callbacks
static FlMethodErrorResponse* scan_listen_cb(FlEventChannel* channel,
                                              FlValue* args,
                                              gpointer user_data) {
  BlePlusPlugin* self = BLE_PLUS_PLUGIN(user_data);
  self->scan_sink = fl_event_channel_get_event_sink(channel);
  return nullptr;
}

static FlMethodErrorResponse* scan_cancel_cb(FlEventChannel* channel,
                                              FlValue* args,
                                              gpointer user_data) {
  BlePlusPlugin* self = BLE_PLUS_PLUGIN(user_data);
  self->scan_sink = nullptr;
  return nullptr;
}

static FlMethodErrorResponse* connection_listen_cb(FlEventChannel* channel,
                                                    FlValue* args,
                                                    gpointer user_data) {
  BlePlusPlugin* self = BLE_PLUS_PLUGIN(user_data);
  self->connection_sink = fl_event_channel_get_event_sink(channel);
  return nullptr;
}

static FlMethodErrorResponse* connection_cancel_cb(FlEventChannel* channel,
                                                    FlValue* args,
                                                    gpointer user_data) {
  BlePlusPlugin* self = BLE_PLUS_PLUGIN(user_data);
  self->connection_sink = nullptr;
  return nullptr;
}

static FlMethodErrorResponse* char_listen_cb(FlEventChannel* channel,
                                              FlValue* args,
                                              gpointer user_data) {
  BlePlusPlugin* self = BLE_PLUS_PLUGIN(user_data);
  self->characteristic_sink = fl_event_channel_get_event_sink(channel);
  return nullptr;
}

static FlMethodErrorResponse* char_cancel_cb(FlEventChannel* channel,
                                              FlValue* args,
                                              gpointer user_data) {
  BlePlusPlugin* self = BLE_PLUS_PLUGIN(user_data);
  self->characteristic_sink = nullptr;
  return nullptr;
}

void ble_plus_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  BlePlusPlugin* plugin = BLE_PLUS_PLUGIN(
      g_object_new(ble_plus_plugin_get_type(), nullptr));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  FlBinaryMessenger* messenger = fl_plugin_registrar_get_messenger(registrar);

  // Method channel
  g_autoptr(FlMethodChannel) method_channel =
      fl_method_channel_new(messenger, "ble_plus/methods", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(method_channel, method_call_cb,
                                            g_object_ref(plugin),
                                            g_object_unref);

  // Event channels
  g_autoptr(FlEventChannel) scan_channel =
      fl_event_channel_new(messenger, "ble_plus/scan", FL_METHOD_CODEC(codec));
  fl_event_channel_set_stream_handler(scan_channel,
                                       scan_listen_cb, scan_cancel_cb,
                                       g_object_ref(plugin), g_object_unref);

  g_autoptr(FlEventChannel) connection_channel =
      fl_event_channel_new(messenger, "ble_plus/connection", FL_METHOD_CODEC(codec));
  fl_event_channel_set_stream_handler(connection_channel,
                                       connection_listen_cb, connection_cancel_cb,
                                       g_object_ref(plugin), g_object_unref);

  g_autoptr(FlEventChannel) char_channel =
      fl_event_channel_new(messenger, "ble_plus/characteristic", FL_METHOD_CODEC(codec));
  fl_event_channel_set_stream_handler(char_channel,
                                       char_listen_cb, char_cancel_cb,
                                       g_object_ref(plugin), g_object_unref);

  g_object_unref(plugin);
}
