class BackgroundSettings {
  final String? iosRestorationIdentifier;
  final String? androidNotificationTitle;
  final String? androidNotificationBody;
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

