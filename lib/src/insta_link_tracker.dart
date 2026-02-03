import "dart:async";

import "package:flutter/services.dart";

class InstaLinkTracker {
  static const MethodChannel _methodChannel = MethodChannel(
    "insta_link_tracker/methods",
  );
  static const EventChannel _eventChannel = EventChannel(
    "insta_link_tracker/events",
  );

  Stream<Map<String, dynamic>> get events =>
      _eventChannel.receiveBroadcastStream().map((dynamic event) {
        if (event is Map) {
          return Map<String, dynamic>.from(event);
        }
        return <String, dynamic>{
          "type": "state",
          "status": "error",
          "message": "Invalid native event payload.",
        };
      });

  Future<bool> init() async {
    final bool? result = await _methodChannel.invokeMethod<bool>("init");
    return result ?? false;
  }

  Future<List<Map<String, dynamic>>> listDevices() async {
    final List<dynamic>? devices = await _methodChannel
        .invokeMethod<List<dynamic>>("listDevices");
    if (devices == null) {
      return <Map<String, dynamic>>[];
    }
    return devices
        .whereType<Map>()
        .map((Map<dynamic, dynamic> item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  Future<bool> connectDevice({required int vid, required int pid}) async {
    final bool? result = await _methodChannel.invokeMethod<bool>(
      "connectDevice",
      <String, dynamic>{"vid": vid, "pid": pid},
    );
    return result ?? false;
  }

  Future<bool> startTracking() async {
    final bool? result = await _methodChannel.invokeMethod<bool>(
      "startTracking",
    );
    return result ?? false;
  }

  Future<bool> stopTracking() async {
    final bool? result = await _methodChannel.invokeMethod<bool>(
      "stopTracking",
    );
    return result ?? false;
  }

  Future<bool> pauseTracking() async {
    final bool? result = await _methodChannel.invokeMethod<bool>(
      "pauseTracking",
    );
    return result ?? false;
  }

  Future<bool> setPid({
    required double kpX,
    required double kiX,
    required double kdX,
    required double kpY,
    required double kiY,
    required double kdY,
  }) async {
    final bool? result = await _methodChannel.invokeMethod<bool>(
      "setPid",
      <String, dynamic>{
        "kpX": kpX,
        "kiX": kiX,
        "kdX": kdX,
        "kpY": kpY,
        "kiY": kiY,
        "kdY": kdY,
      },
    );
    return result ?? false;
  }

  Future<bool> setTargetPolicy(String mode) async {
    final bool? result = await _methodChannel.invokeMethod<bool>(
      "setTargetPolicy",
      <String, dynamic>{"mode": mode},
    );
    return result ?? false;
  }

  Future<bool> reconnect() async {
    final bool? result = await _methodChannel.invokeMethod<bool>("reconnect");
    return result ?? false;
  }

  Future<bool> activateCamera() async {
    final bool? result = await _methodChannel.invokeMethod<bool>(
      "activateCamera",
    );
    return result ?? false;
  }

  Future<bool> manualControl({
    required double pan,
    required double tilt,
    int durationMs = 350,
  }) async {
    final bool? result = await _methodChannel.invokeMethod<bool>(
      "manualControl",
      <String, dynamic>{
        "pan": pan,
        "tilt": tilt,
        "durationMs": durationMs,
      },
    );
    return result ?? false;
  }

  Future<bool> manualZoom({
    required double zoom,
    int durationMs = 300,
  }) async {
    final bool? result = await _methodChannel.invokeMethod<bool>(
      "manualZoom",
      <String, dynamic>{
        "zoom": zoom,
        "durationMs": durationMs,
      },
    );
    return result ?? false;
  }

  Future<Uint8List?> getPreviewJpeg() async {
    final Uint8List? data = await _methodChannel.invokeMethod<Uint8List>(
      "getPreviewJpeg",
    );
    return data;
  }

  Future<bool> dumpPreview() async {
    final bool? result = await _methodChannel.invokeMethod<bool>("dumpPreview");
    return result ?? false;
  }

  Future<bool> recoverPreview() async {
    final bool? result = await _methodChannel.invokeMethod<bool>("recoverPreview");
    return result ?? false;
  }

  Future<bool> dispose() async {
    final bool? result = await _methodChannel.invokeMethod<bool>("dispose");
    return result ?? false;
  }
}
