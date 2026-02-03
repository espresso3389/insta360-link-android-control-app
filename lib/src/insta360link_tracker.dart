import "dart:async";

import "package:flutter/services.dart";

abstract class Insta360LinkEvent {
  const Insta360LinkEvent(this.type);

  final String type;

  static Insta360LinkEvent fromDynamic(dynamic event) {
    if (event is Map) {
      final Map<String, dynamic> data = Map<String, dynamic>.from(event);
      final String type = (data["type"] ?? "").toString();
      switch (type) {
        case "state":
          return Insta360LinkStateEvent(
            status: (data["status"] ?? "unknown").toString(),
            message: (data["message"] ?? "").toString(),
          );
        case "telemetry":
          return Insta360LinkTelemetryEvent(
            fps: _asDouble(data["fps"], 0),
            latencyMs: _asDouble(data["latencyMs"], 0),
            pan: _asDouble(data["pan"], 0),
            tilt: _asDouble(data["tilt"], 0),
            patrol: data["patrol"] == true,
            source: (data["source"] ?? "").toString(),
          );
        case "face":
          return Insta360LinkFaceEvent(
            x: _asDouble(data["x"], 0.0),
            y: _asDouble(data["y"], 0.0),
            w: _asDouble(data["w"], 0.0),
            h: _asDouble(data["h"], 0.0),
          );
        case "stream":
          return Insta360LinkStreamEvent(
            kbps: _asDouble(data["kbps"], 0),
            packets: _asInt(data["packets"], 0),
            frames: _asInt(data["frames"], 0),
            bytes: _asInt(data["bytes"], 0),
            source: (data["source"] ?? "").toString(),
          );
        default:
          return Insta360LinkUnknownEvent(type: type, payload: data);
      }
    }
    return const Insta360LinkStateEvent(
      status: "error",
      message: "Invalid native event payload.",
    );
  }

  static double _asDouble(dynamic value, double fallback) {
    if (value is num) {
      return value.toDouble();
    }
    return fallback;
  }

  static int _asInt(dynamic value, int fallback) {
    if (value is num) {
      return value.toInt();
    }
    return fallback;
  }
}

class Insta360LinkStateEvent extends Insta360LinkEvent {
  const Insta360LinkStateEvent({required this.status, required this.message})
    : super("state");

  final String status;
  final String message;
}

class Insta360LinkTelemetryEvent extends Insta360LinkEvent {
  const Insta360LinkTelemetryEvent({
    required this.fps,
    required this.latencyMs,
    required this.pan,
    required this.tilt,
    required this.patrol,
    required this.source,
  }) : super("telemetry");

  final double fps;
  final double latencyMs;
  final double pan;
  final double tilt;
  final bool patrol;
  final String source;
}

class Insta360LinkFaceEvent extends Insta360LinkEvent {
  const Insta360LinkFaceEvent({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
  }) : super("face");

  final double x;
  final double y;
  final double w;
  final double h;
}

class Insta360LinkStreamEvent extends Insta360LinkEvent {
  const Insta360LinkStreamEvent({
    required this.kbps,
    required this.packets,
    required this.frames,
    required this.bytes,
    required this.source,
  }) : super("stream");

  final double kbps;
  final int packets;
  final int frames;
  final int bytes;
  final String source;
}

class Insta360LinkUnknownEvent extends Insta360LinkEvent {
  const Insta360LinkUnknownEvent({required this.type, required this.payload})
    : super(type);

  @override
  final String type;
  final Map<String, dynamic> payload;
}

class Insta360LinkDeviceInfo {
  const Insta360LinkDeviceInfo({
    required this.name,
    required this.vid,
    required this.pid,
    required this.isUvc,
    required this.hasPermission,
  });

  final String name;
  final int vid;
  final int pid;
  final bool isUvc;
  final bool hasPermission;

  static Insta360LinkDeviceInfo fromMap(Map<dynamic, dynamic> data) {
    return Insta360LinkDeviceInfo(
      name: (data["name"] ?? "device").toString(),
      vid: (data["vid"] as num?)?.toInt() ?? 0,
      pid: (data["pid"] as num?)?.toInt() ?? 0,
      isUvc: data["isUvc"] == true,
      hasPermission: data["hasPermission"] == true,
    );
  }
}

class Insta360LinkPid {
  const Insta360LinkPid({
    required this.kpX,
    required this.kiX,
    required this.kdX,
    required this.kpY,
    required this.kiY,
    required this.kdY,
  });

  final double kpX;
  final double kiX;
  final double kdX;
  final double kpY;
  final double kiY;
  final double kdY;

  static Insta360LinkPid? fromMap(Map<dynamic, dynamic>? data) {
    if (data == null) {
      return null;
    }
    double asDouble(dynamic value) => value is num ? value.toDouble() : 0;
    return Insta360LinkPid(
      kpX: asDouble(data["kpX"]),
      kiX: asDouble(data["kiX"]),
      kdX: asDouble(data["kdX"]),
      kpY: asDouble(data["kpY"]),
      kiY: asDouble(data["kiY"]),
      kdY: asDouble(data["kdY"]),
    );
  }
}

class Insta360LinkTracker {
  static const MethodChannel _methodChannel = MethodChannel(
    "insta_link_tracker/methods",
  );
  static const EventChannel _eventChannel = EventChannel(
    "insta_link_tracker/events",
  );

  Stream<Insta360LinkEvent> get events =>
      _eventChannel.receiveBroadcastStream().map(Insta360LinkEvent.fromDynamic);

  Future<Insta360LinkPid?> getPid() async {
    final Map<dynamic, dynamic>? data = await _methodChannel
        .invokeMethod<Map<dynamic, dynamic>>("getPid");
    return Insta360LinkPid.fromMap(data);
  }

  Future<List<double>?> extractFaceEmbedding({
    required Uint8List jpeg,
  }) async {
    final List<dynamic>? data = await _methodChannel.invokeMethod<List<dynamic>>(
      "extractFaceEmbedding",
      <String, dynamic>{"jpeg": jpeg},
    );
    if (data == null) {
      return null;
    }
    return data.whereType<num>().map((num v) => v.toDouble()).toList();
  }

  Future<bool> init() async {
    final bool? result = await _methodChannel.invokeMethod<bool>("init");
    return result ?? false;
  }

  Future<List<Insta360LinkDeviceInfo>> listDevices() async {
    final List<dynamic>? devices = await _methodChannel
        .invokeMethod<List<dynamic>>("listDevices");
    if (devices == null) {
      return <Insta360LinkDeviceInfo>[];
    }
    return devices
        .whereType<Map>()
        .map(Insta360LinkDeviceInfo.fromMap)
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
      <String, dynamic>{"pan": pan, "tilt": tilt, "durationMs": durationMs},
    );
    return result ?? false;
  }

  Future<bool> manualZoom({required double zoom, int durationMs = 300}) async {
    final bool? result = await _methodChannel.invokeMethod<bool>(
      "manualZoom",
      <String, dynamic>{"zoom": zoom, "durationMs": durationMs},
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
    final bool? result = await _methodChannel.invokeMethod<bool>(
      "recoverPreview",
    );
    return result ?? false;
  }

  Future<bool> dispose() async {
    final bool? result = await _methodChannel.invokeMethod<bool>("dispose");
    return result ?? false;
  }
}
