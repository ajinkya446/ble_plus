/// Settings for background BLE operation.
class BackgroundSettings {
  /// iOS: state restoration identifier for CBCentralManager.
  final String? iosRestorationIdentifier;

  /// Android: title for the foreground service notification.
  final String? androidNotificationTitle;

  /// Android: body text for the foreground service notification.
  final String? androidNotificationBody;

  /// Android: notification channel ID.
  final String? androidNotificationChannelId;

  const BackgroundSettings({
    this.iosRestorationIdentifier,
    this.androidNotificationTitle,
    this.androidNotificationBody,
    this.androidNotificationChannelId,
  });

  Map<String, dynamic> toMap() => {
    'iosRestorationIdentifier': iosRestorationIdentifier,
    'androidNotificationTitle': androidNotificationTitle,
    'androidNotificationBody': androidNotificationBody,
    'androidNotificationChannelId': androidNotificationChannelId,
  };
}

