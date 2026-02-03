import "dart:async";
import "dart:typed_data";
import "dart:math" as Math;

import "package:flutter/material.dart";
import "package:image/image.dart" as img;

import "insta360link_tracker.dart";
import "data/face_person.dart";
import "data/isar_service.dart";

enum _ControlMode { automatic, manual }

class TrackingPage extends StatefulWidget {
  const TrackingPage({super.key});

  @override
  State<TrackingPage> createState() => _TrackingPageState();
}

class _TrackingPageState extends State<TrackingPage> {
  final Insta360LinkTracker _tracker = Insta360LinkTracker();

  StreamSubscription<Insta360LinkEvent>? _eventSub;
  Timer? _previewTimer;
  List<Insta360LinkDeviceInfo> _devices = <Insta360LinkDeviceInfo>[];
  String _status = "idle";
  String _message = "Press Initialize to start.";
  bool _trackingActive = false;
  _ControlMode _mode = _ControlMode.automatic;
  int _lastGimbalCmdMs = 0;
  IsarService? _isar;
  List<FacePerson> _people = <FacePerson>[];
  String _serverUrl = "";
  final TextEditingController _personNameController = TextEditingController();
  final TextEditingController _serverUrlController = TextEditingController();

  double _fps = 0;
  double _latencyMs = 0;
  double _pan = 0;
  double _tilt = 0;
  Insta360LinkFaceEvent? _face;
  String? _identityLabel;
  double? _identityConfidence;
  bool _identityInFlight = false;
  int _lastIdentifyMs = 0;
  int _lastFaceMs = 0;
  int _faceConsecutive = 0;
  final double _localMatchThreshold = 0.55;
  double _streamKbps = 0;
  int _streamPackets = 0;
  int _streamFrames = 0;
  int _streamBytes = 0;
  String _streamSource = "uvc";
  String _connectedDeviceName = "-";
  Uint8List? _previewJpeg;
  String _modeOverlay = "Auto";

  double _kpX = -1.20;
  double _kiX = 0;
  double _kdX = -0.12;
  double _kpY = 1.00;
  double _kiY = 0;
  double _kdY = 0.10;

  @override
  void initState() {
    super.initState();
    _eventSub = _tracker.events.listen(_onEvent);
    _previewTimer = Timer.periodic(const Duration(milliseconds: 220), (_) {
      unawaited(_refreshPreviewFrame());
    });
    unawaited(_initStorage());
    unawaited(_syncPidFromDevice());
    unawaited(_autoBootstrap());
  }

  @override
  void dispose() {
    _previewTimer?.cancel();
    _eventSub?.cancel();
    _personNameController.dispose();
    _serverUrlController.dispose();
    _tracker.dispose();
    super.dispose();
  }

  Future<void> _initStorage() async {
    final isar = await IsarService.getInstance();
    final settings = await isar.getSettings();
    final people = await isar.listPeople();
    if (!mounted) {
      return;
    }
    setState(() {
      _isar = isar;
      _serverUrl = settings.serverUrl;
      _serverUrlController.text = settings.serverUrl;
      _people = people;
    });
  }

  Future<void> _refreshPreviewFrame() async {
    final Uint8List? frame = await _tracker.getPreviewJpeg();
    if (!mounted || frame == null || frame.isEmpty) {
      return;
    }
    setState(() {
      _previewJpeg = frame;
    });
  }

  Uint8List? _captureFaceJpeg() {
    final face = _face;
    final jpeg = _previewJpeg;
    if (face == null || jpeg == null || jpeg.isEmpty) {
      return null;
    }
    final decoded = img.decodeImage(jpeg);
    if (decoded == null) {
      return null;
    }
    final double x = face.x;
    final double y = face.y;
    final double w = face.w;
    final double h = face.h;
    if (w <= 0 || h <= 0) {
      return null;
    }
    final int imgW = decoded.width;
    final int imgH = decoded.height;
    final double pad = 0.2;
    final int left =
        ((x - pad * w) * imgW).clamp(0, imgW - 1).toInt();
    final int top =
        ((y - pad * h) * imgH).clamp(0, imgH - 1).toInt();
    final int right =
        ((x + (1 + pad) * w) * imgW).clamp(1, imgW).toInt();
    final int bottom =
        ((y + (1 + pad) * h) * imgH).clamp(1, imgH).toInt();
    final int cropW = (right - left).clamp(1, imgW);
    final int cropH = (bottom - top).clamp(1, imgH);
    final cropped = img.copyCrop(
      decoded,
      x: left,
      y: top,
      width: cropW,
      height: cropH,
    );
    final List<int> faceJpeg = img.encodeJpg(cropped, quality: 90);
    return Uint8List.fromList(faceJpeg);
  }

  Future<void> _maybeIdentifyFace() async {
    if (_identityInFlight) {
      return;
    }
    if (_faceConsecutive < 10) {
      return;
    }
    final int now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastIdentifyMs < 3000) {
      return;
    }
    final Uint8List? faceJpeg = _captureFaceJpeg();
    if (faceJpeg == null) {
      return;
    }
    _identityInFlight = true;
    _lastIdentifyMs = now;
    try {
      final List<double>? embedding =
          await _tracker.extractFaceEmbedding(jpeg: faceJpeg);
      if (embedding == null || embedding.isEmpty) {
        return;
      }
      final _IdentityMatch? match = _matchEmbedding(embedding);
      if (!mounted) {
        return;
      }
      setState(() {
        if (match == null || match.score < _localMatchThreshold) {
          _identityLabel = "Unknown";
          _identityConfidence = null;
        } else {
          _identityLabel = match.name;
          _identityConfidence = match.score * 100.0;
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _identityLabel = null;
          _identityConfidence = null;
        });
      }
    } finally {
      _identityInFlight = false;
      _faceConsecutive = 0;
    }
  }

  _IdentityMatch? _matchEmbedding(List<double> query) {
    double bestScore = -1;
    String? bestName;
    final List<double> normQuery = _normalizeEmbedding(query);
    for (final FacePerson person in _people) {
      final List<double>? embedding = person.faceEmbedding;
      if (embedding == null || embedding.isEmpty) {
        continue;
      }
      final double score = _cosineSimilarity(
        normQuery,
        _normalizeEmbedding(embedding),
      );
      if (score > bestScore) {
        bestScore = score;
        bestName = person.name;
      }
    }
    if (bestName == null) {
      return null;
    }
    return _IdentityMatch(name: bestName, score: bestScore);
  }

  List<double> _normalizeEmbedding(List<double> vector) {
    double sum = 0;
    for (final double v in vector) {
      sum += v * v;
    }
    final double norm = sum == 0 ? 1 : Math.sqrt(sum);
    return vector.map((double v) => v / norm).toList(growable: false);
  }

  double _cosineSimilarity(List<double> a, List<double> b) {
    final int n = a.length < b.length ? a.length : b.length;
    double dot = 0;
    for (int i = 0; i < n; i++) {
      dot += a[i] * b[i];
    }
    return dot;
  }

  Future<void> _syncPidFromDevice() async {
    final Insta360LinkPid? pid = await _tracker.getPid();
    if (!mounted || pid == null) {
      return;
    }
    setState(() {
      _kpX = pid.kpX;
      _kiX = pid.kiX;
      _kdX = pid.kdX;
      _kpY = pid.kpY;
      _kiY = pid.kiY;
      _kdY = pid.kdY;
    });
  }

  void _onEvent(Insta360LinkEvent event) {
    if (!mounted) {
      return;
    }
    setState(() {
      if (event is Insta360LinkStateEvent) {
        _status = event.status;
        _message = event.message;
        // Keep mode explicit; do not auto-flip manual mode on status events.
      } else if (event is Insta360LinkTelemetryEvent) {
        _fps = event.fps;
        _latencyMs = event.latencyMs;
        _pan = event.pan;
        _tilt = event.tilt;
        final bool patrol = event.patrol;
        if (_mode == _ControlMode.manual) {
          _modeOverlay = "Manual";
        } else if (patrol) {
          _modeOverlay = "Patrolling";
        } else {
          _modeOverlay = "Tracking";
        }
      } else if (event is Insta360LinkFaceEvent) {
        _face = event;
        final int now = DateTime.now().millisecondsSinceEpoch;
        if (now - _lastFaceMs > 600) {
          _faceConsecutive = 0;
        }
        _lastFaceMs = now;
        _faceConsecutive += 1;
      } else if (event is Insta360LinkStreamEvent) {
        _streamKbps = event.kbps;
        _streamPackets = event.packets;
        _streamFrames = event.frames;
        _streamBytes = event.bytes;
        _streamSource = event.source;
      }
    });
    if (event is Insta360LinkFaceEvent) {
      unawaited(_maybeIdentifyFace());
    }
    if (event is Insta360LinkTelemetryEvent &&
        _mode == _ControlMode.automatic &&
        !event.source.startsWith("yolov8n-face-tflite")) {
      unawaited(_maybeSendTrackingGimbal(event.pan, event.tilt, event.fps));
    }
  }

  Future<void> _maybeSendTrackingGimbal(
    double pan,
    double tilt,
    double fps,
  ) async {
    if (!_trackingActive || _mode != _ControlMode.automatic || fps <= 0) {
      return;
    }
    final int now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastGimbalCmdMs < 180) {
      return;
    }
    final double panCmd = (pan * 60).clamp(-1.0, 1.0);
    final double tiltCmd = (tilt * 60).clamp(-1.0, 1.0);
    if (panCmd.abs() < 0.05 && tiltCmd.abs() < 0.05) {
      return;
    }
    _lastGimbalCmdMs = now;
    await _tracker.manualControl(pan: panCmd, tilt: tiltCmd, durationMs: 200);
  }

  Future<void> _refreshDevices() async {
    final List<Insta360LinkDeviceInfo> devices = await _tracker.listDevices();
    setState(() {
      _devices = devices;
    });
  }

  Future<void> _autoBootstrap() async {
    setState(() {
      _message = "Auto starting camera + tracking...";
    });
    final bool inited = await _tracker.init();
    if (!inited) {
      setState(() {
        _status = "error";
        _message = "Native init failed.";
      });
      return;
    }
    await _syncPidFromDevice();
    await _refreshDevices();
    bool connected = false;
    bool started = false;
    for (int attempt = 0; attempt < 6; attempt++) {
      connected = await _connectFirstDevice(silent: true);
      if (!connected) {
        await Future<void>.delayed(const Duration(milliseconds: 700));
        await _refreshDevices();
        continue;
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
      started = await _startTracking(silent: true);
      if (started) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 700));
    }
    if (!connected) {
      setState(() {
        _status = "error";
        _message = "Auto connect failed. Check USB/hub, then use Reconnect.";
      });
      return;
    }
    setState(() {
      _mode = _ControlMode.automatic;
      _status = started ? "running" : "connected";
      _trackingActive = started;
      _modeOverlay = started ? "Tracking" : "Auto";
      _message = started
          ? "Automatic tracking active."
          : "Connected. Tap Automatic to start tracking.";
    });
  }

  Future<bool> _connectFirstDevice({bool silent = false}) async {
    if (_devices.isEmpty) {
      if (!silent) {
        setState(() {
          _status = "error";
          _message = "No USB devices found.";
        });
      }
      return false;
    }
    final Insta360LinkDeviceInfo? first = _devices
        .cast<Insta360LinkDeviceInfo?>()
        .firstWhere(
          (Insta360LinkDeviceInfo? d) => d?.isUvc == true,
          orElse: () => null,
        );
    if (first == null) {
      setState(() {
        _status = "error";
        _message = "No UVC camera device found. Hub/device order changed.";
      });
      return false;
    }
    final bool ok = await _tracker.connectDevice(
      vid: first.vid,
      pid: first.pid,
    );
    if (!silent) {
      setState(() {
        _connectedDeviceName = first.name;
        _status = ok ? "connected" : "error";
        _message = ok ? "Connected to ${first.name}." : "Connect failed.";
      });
    } else if (ok) {
      _connectedDeviceName = first.name;
    }
    return ok;
  }

  Future<bool> _startTracking({bool silent = false}) async {
    await _tracker.setPid(
      kpX: _kpX,
      kiX: _kiX,
      kdX: _kdX,
      kpY: _kpY,
      kiY: _kiY,
      kdY: _kdY,
    );
    await Future<void>.delayed(const Duration(milliseconds: 450));
    final bool ok = await _tracker.startTracking();
    _trackingActive = ok;
    if (!silent) {
      setState(() {
        _status = ok ? "running" : "error";
        _mode = ok ? _ControlMode.automatic : _mode;
        _modeOverlay = ok ? "Tracking" : _modeOverlay;
        _message = ok ? "Automatic tracking active." : "Start failed.";
      });
    }
    return ok;
  }

  Future<void> _setAutomaticMode() async {
    final bool ok = await _startTracking();
    if (ok) {
      setState(() {
        _mode = _ControlMode.automatic;
      });
    }
  }

  Future<void> _enterManualMode() async {
    await _tracker.pauseTracking();
    _trackingActive = false;
    setState(() {
      _mode = _ControlMode.manual;
      _trackingActive = false;
      _modeOverlay = "Manual";
      _status = "connected";
      _message = "Manual mode active. Press Automatic to resume face tracking.";
    });
  }

  Future<void> _manualZoom(double zoom) async {
    await _enterManualMode();
    final bool ok = await _tracker.manualZoom(zoom: zoom, durationMs: 350);
    setState(() {
      _message = ok
          ? "Manual zoom ${zoom > 0 ? "in" : "out"}"
          : "Manual zoom failed.";
      if (!ok) {
        _status = "error";
      }
    });
  }

  Future<void> _manualMove(double pan, double tilt) async {
    await _enterManualMode();
    final bool ok = await _tracker.manualControl(
      pan: pan,
      tilt: tilt,
      durationMs: 550,
    );
    setState(() {
      _message = ok
          ? "Manual move pan=${pan.toStringAsFixed(2)}, tilt=${tilt.toStringAsFixed(2)}"
          : "Manual move failed.";
      if (!ok) {
        _status = "error";
      }
    });
  }

  Future<void> _dumpPreview() async {
    final bool ok = await _tracker.dumpPreview();
    setState(() {
      _message = ok
          ? "Preview dumped to /sdcard/Download/preview.jpg"
          : "Preview dump failed.";
      if (!ok) {
        _status = "error";
      }
    });
  }

  Future<void> _recoverPreview() async {
    final bool ok = await _tracker.recoverPreview();
    setState(() {
      _message = ok
          ? "Recovery sequence started."
          : "Recovery sequence failed.";
      if (!ok) {
        _status = "error";
      }
    });
  }

  Future<void> _saveServerUrl(String url) async {
    final isar = _isar;
    if (isar == null) {
      return;
    }
    await isar.updateServerUrl(url);
    setState(() {
      _serverUrl = url;
      _serverUrlController.text = url;
      _message = "Server URL saved.";
    });
  }

  Future<void> _refreshPeople() async {
    final isar = _isar;
    if (isar == null) {
      return;
    }
    final people = await isar.listPeople();
    if (!mounted) {
      return;
    }
    setState(() {
      _people = people;
    });
  }

  Future<void> _openPersonGroup(_PersonGroup group) async {
    final isar = _isar;
    if (isar == null || !mounted) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => _PersonDetailPage(
          isar: isar,
          initialName: group.name,
          initialFaces: group.faces,
        ),
      ),
    );
    await _refreshPeople();
  }

  Future<void> _enrollCurrentFace(String name) async {
    final isar = _isar;
    if (isar == null) {
      return;
    }
    final Uint8List? faceJpeg = _captureFaceJpeg();
    if (faceJpeg == null) {
      setState(() {
        _message = "No face/preview to enroll.";
      });
      return;
    }
    final List<double>? embedding =
        await _tracker.extractFaceEmbedding(jpeg: faceJpeg);
    if (embedding == null || embedding.isEmpty) {
      setState(() {
        _message = "Failed to extract face embedding.";
      });
      return;
    }
    final face = _face;
    final person = FacePerson()
      ..name = name.trim()
      ..faceJpegBytes = Uint8List.fromList(faceJpeg)
      ..faceEmbedding = embedding
      ..boxX = face?.x
      ..boxY = face?.y
      ..boxW = face?.w
      ..boxH = face?.h;
    await isar.upsertPerson(person);
    await _refreshPeople();
    if (mounted) {
      setState(() {
        _message = "Enrolled ${person.name}.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isPortrait =
        MediaQuery.of(context).size.height >= MediaQuery.of(context).size.width;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: isPortrait
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    LayoutBuilder(
                      builder:
                          (BuildContext context, BoxConstraints constraints) {
                            final double w = constraints.maxWidth;
                            final double h = w * 9 / 16;
                            return SizedBox(
                        height: h,
                        child: _PreviewCard(
                          face: _face,
                          jpegFrame: _previewJpeg,
                          modeOverlay: _modeOverlay,
                          identityLabel: _identityLabel,
                          identityConfidence: _identityConfidence,
                        ),
                      );
                    },
                  ),
                    const SizedBox(height: 8),
                    Expanded(
                      flex: 4,
                      child: _TabPanel(
                        mode: _mode,
                        fps: _fps,
                        latencyMs: _latencyMs,
                        pan: _pan,
                        tilt: _tilt,
                        connectedDeviceName: _connectedDeviceName,
                        devices: _devices,
                        streamSource: _streamSource,
                        streamKbps: _streamKbps,
                        streamPackets: _streamPackets,
                        streamFrames: _streamFrames,
                        streamBytes: _streamBytes,
                        kpX: _kpX,
                        kiX: _kiX,
                        kdX: _kdX,
                        kpY: _kpY,
                        kiY: _kiY,
                        kdY: _kdY,
                        status: _status,
                        message: _message,
                        onMove: _manualMove,
                        onZoom: _manualZoom,
                        onAutomatic: _setAutomaticMode,
                        onManual: _enterManualMode,
                        onDumpPreview: _dumpPreview,
                        onRecoverPreview: _recoverPreview,
                        people: _people,
                        onOpenPerson: _openPersonGroup,
                        onEnroll: (String name) => _enrollCurrentFace(name),
                        nameController: _personNameController,
                        serverUrl: _serverUrl,
                        urlController: _serverUrlController,
                        onSaveServerUrl: _saveServerUrl,
                        onPidChanged:
                            (
                              double kpX,
                              double kiX,
                              double kdX,
                              double kpY,
                              double kiY,
                              double kdY,
                            ) {
                              setState(() {
                                _kpX = kpX;
                                _kiX = kiX;
                                _kdX = kdX;
                                _kpY = kpY;
                                _kiY = kiY;
                                _kdY = kdY;
                              });
                            },
                        onInit: () async {
                          final bool ok = await _tracker.init();
                          setState(() {
                            _status = ok ? "ready" : "error";
                            _message = ok
                                ? "Native init done."
                                : "Native init failed.";
                          });
                          if (ok) {
                            await _syncPidFromDevice();
                          }
                          await _refreshDevices();
                        },
                        onRefresh: _refreshDevices,
                        onReconnect: () async {
                          final bool ok = await _tracker.reconnect();
                          setState(() {
                            _status = ok ? "connected" : "error";
                            _message = ok
                                ? "Reconnect done."
                                : "Reconnect failed.";
                          });
                        },
                        onConnectFirst: () async {
                          final bool ok = await _connectFirstDevice(
                            silent: false,
                          );
                          if (ok) {
                            setState(() {
                              _status = "connected";
                              _message = "Connected to UVC device.";
                            });
                          }
                        },
                        onActivateCamera: () async {
                          final bool ok = await _tracker.activateCamera();
                          setState(() {
                            _status = ok ? "connected" : "error";
                            _message = ok
                                ? "Camera stream active."
                                : "Camera activate failed.";
                          });
                        },
                        onStartTracking: () async {
                          await _setAutomaticMode();
                        },
                        onStopTracking: () async {
                          final bool ok = await _tracker.stopTracking();
                          setState(() {
                            _trackingActive = false;
                            _status = ok ? "connected" : "error";
                            _message = ok
                                ? "Tracking stopped."
                                : "Stop failed.";
                          });
                        },
                      ),
                    ),
                  ],
                )
              : Row(
                  children: <Widget>[
                    Expanded(
                    child: _PreviewCard(
                      face: _face,
                      jpegFrame: _previewJpeg,
                      modeOverlay: _modeOverlay,
                      identityLabel: _identityLabel,
                      identityConfidence: _identityConfidence,
                    ),
                  ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 340,
                      child: _TabPanel(
                        mode: _mode,
                        fps: _fps,
                        latencyMs: _latencyMs,
                        pan: _pan,
                        tilt: _tilt,
                        connectedDeviceName: _connectedDeviceName,
                        devices: _devices,
                        streamSource: _streamSource,
                        streamKbps: _streamKbps,
                        streamPackets: _streamPackets,
                        streamFrames: _streamFrames,
                        streamBytes: _streamBytes,
                        kpX: _kpX,
                        kiX: _kiX,
                        kdX: _kdX,
                        kpY: _kpY,
                        kiY: _kiY,
                        kdY: _kdY,
                        status: _status,
                        message: _message,
                        onMove: _manualMove,
                        onZoom: _manualZoom,
                        onAutomatic: _setAutomaticMode,
                        onManual: _enterManualMode,
                        onDumpPreview: _dumpPreview,
                        onRecoverPreview: _recoverPreview,
                        people: _people,
                        onOpenPerson: _openPersonGroup,
                        onEnroll: (String name) => _enrollCurrentFace(name),
                        nameController: _personNameController,
                        serverUrl: _serverUrl,
                        urlController: _serverUrlController,
                        onSaveServerUrl: _saveServerUrl,
                        onPidChanged:
                            (
                              double kpX,
                              double kiX,
                              double kdX,
                              double kpY,
                              double kiY,
                              double kdY,
                            ) {
                              setState(() {
                                _kpX = kpX;
                                _kiX = kiX;
                                _kdX = kdX;
                                _kpY = kpY;
                                _kiY = kiY;
                                _kdY = kdY;
                              });
                            },
                        onInit: () async {
                          final bool ok = await _tracker.init();
                          setState(() {
                            _status = ok ? "ready" : "error";
                            _message = ok
                                ? "Native init done."
                                : "Native init failed.";
                          });
                          if (ok) {
                            await _syncPidFromDevice();
                          }
                          await _refreshDevices();
                        },
                        onRefresh: _refreshDevices,
                        onReconnect: () async {
                          final bool ok = await _tracker.reconnect();
                          setState(() {
                            _status = ok ? "connected" : "error";
                            _message = ok
                                ? "Reconnect done."
                                : "Reconnect failed.";
                          });
                        },
                        onConnectFirst: () async {
                          final bool ok = await _connectFirstDevice(
                            silent: false,
                          );
                          if (ok) {
                            setState(() {
                              _status = "connected";
                              _message = "Connected to UVC device.";
                            });
                          }
                        },
                        onActivateCamera: () async {
                          final bool ok = await _tracker.activateCamera();
                          setState(() {
                            _status = ok ? "connected" : "error";
                            _message = ok
                                ? "Camera stream active."
                                : "Camera activate failed.";
                          });
                        },
                        onStartTracking: () async {
                          await _setAutomaticMode();
                        },
                        onStopTracking: () async {
                          final bool ok = await _tracker.stopTracking();
                          setState(() {
                            _trackingActive = false;
                            _status = ok ? "connected" : "error";
                            _message = ok
                                ? "Tracking stopped."
                                : "Stop failed.";
                          });
                        },
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _TabPanel extends StatelessWidget {
  const _TabPanel({
    required this.mode,
    required this.fps,
    required this.latencyMs,
    required this.pan,
    required this.tilt,
    required this.connectedDeviceName,
    required this.devices,
    required this.streamSource,
    required this.streamKbps,
    required this.streamPackets,
    required this.streamFrames,
    required this.streamBytes,
    required this.kpX,
    required this.kiX,
    required this.kdX,
    required this.kpY,
    required this.kiY,
    required this.kdY,
    required this.status,
    required this.message,
    required this.onMove,
    required this.onZoom,
    required this.onAutomatic,
    required this.onManual,
    required this.onDumpPreview,
    required this.onRecoverPreview,
    required this.onPidChanged,
    required this.onInit,
    required this.onRefresh,
    required this.onReconnect,
    required this.onConnectFirst,
    required this.onActivateCamera,
    required this.onStartTracking,
    required this.onStopTracking,
    required this.people,
    required this.onOpenPerson,
    required this.onEnroll,
    required this.nameController,
    required this.serverUrl,
    required this.urlController,
    required this.onSaveServerUrl,
  });

  final _ControlMode mode;
  final double fps;
  final double latencyMs;
  final double pan;
  final double tilt;
  final String connectedDeviceName;
  final List<Insta360LinkDeviceInfo> devices;
  final String streamSource;
  final double streamKbps;
  final int streamPackets;
  final int streamFrames;
  final int streamBytes;
  final double kpX;
  final double kiX;
  final double kdX;
  final double kpY;
  final double kiY;
  final double kdY;
  final String status;
  final String message;
  final Future<void> Function(double pan, double tilt) onMove;
  final Future<void> Function(double zoom) onZoom;
  final Future<void> Function() onAutomatic;
  final Future<void> Function() onManual;
  final Future<void> Function() onDumpPreview;
  final Future<void> Function() onRecoverPreview;
  final void Function(
    double kpX,
    double kiX,
    double kdX,
    double kpY,
    double kiY,
    double kdY,
  )
  onPidChanged;
  final Future<void> Function() onInit;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onReconnect;
  final Future<void> Function() onConnectFirst;
  final Future<void> Function() onActivateCamera;
  final Future<void> Function() onStartTracking;
  final Future<void> Function() onStopTracking;
  final List<FacePerson> people;
  final void Function(_PersonGroup group) onOpenPerson;
  final Future<void> Function(String name) onEnroll;
  final TextEditingController nameController;
  final String serverUrl;
  final TextEditingController urlController;
  final Future<void> Function(String url) onSaveServerUrl;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Column(
        children: <Widget>[
          const TabBar(
            isScrollable: true,
            tabs: <Widget>[
              Tab(text: "Gimbal"),
              Tab(text: "People"),
              Tab(text: "Status"),
              Tab(text: "Settings"),
              Tab(text: "Init"),
            ],
          ),
          const SizedBox(height: 4),
          Expanded(
            child: TabBarView(
              children: <Widget>[
                SingleChildScrollView(
                  child: _GimbalCard(
                    onMove: onMove,
                    onZoom: onZoom,
                    mode: mode,
                    onAutomatic: onAutomatic,
                    onManual: onManual,
                  ),
                ),
                SingleChildScrollView(
                  child: _PeopleTab(
                    people: people,
                    onOpenPerson: onOpenPerson,
                    onEnroll: onEnroll,
                    nameController: nameController,
                  ),
                ),
                SingleChildScrollView(
                  child: _StatusCard(
                    fps: fps,
                    latencyMs: latencyMs,
                    pan: pan,
                    tilt: tilt,
                    connectedDeviceName: connectedDeviceName,
                    totalDevices: devices.length,
                    uvcDevices: devices
                        .where((Insta360LinkDeviceInfo d) => d.isUvc)
                        .length,
                    streamSource: streamSource,
                    streamKbps: streamKbps,
                    streamPackets: streamPackets,
                    streamFrames: streamFrames,
                    streamBytes: streamBytes,
                    onRecoverPreview: onRecoverPreview,
                    onDumpPreview: onDumpPreview,
                  ),
                ),
                SingleChildScrollView(
                  child: _SettingsTab(
                    kpX: kpX,
                    kiX: kiX,
                    kdX: kdX,
                    kpY: kpY,
                    kiY: kiY,
                    kdY: kdY,
                    onPidChanged: onPidChanged,
                    serverUrl: serverUrl,
                    urlController: urlController,
                    onSaveServerUrl: onSaveServerUrl,
                  ),
                ),
                SingleChildScrollView(
                  child: _InitCard(
                    status: status,
                    message: message,
                    devices: devices,
                    onInit: onInit,
                    onRefresh: onRefresh,
                    onReconnect: onReconnect,
                    onConnectFirst: onConnectFirst,
                    onActivateCamera: onActivateCamera,
                    onStartTracking: onStartTracking,
                    onStopTracking: onStopTracking,
                    onRecoverPreview: onRecoverPreview,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({
    required this.face,
    required this.jpegFrame,
    required this.modeOverlay,
    required this.identityLabel,
    required this.identityConfidence,
  });

  final Insta360LinkFaceEvent? face;
  final Uint8List? jpegFrame;
  final String modeOverlay;
  final String? identityLabel;
  final double? identityConfidence;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          if (jpegFrame != null)
            Image.memory(jpegFrame!, fit: BoxFit.cover, gaplessPlayback: true)
          else
            const Center(
              child: Text(
                "Waiting preview frame...",
                style: TextStyle(color: Colors.white70),
              ),
            ),
          CustomPaint(
            painter: _FacePainter(
              face: face,
              identityLabel: identityLabel,
              identityConfidence: identityConfidence,
            ),
          ),
          Positioned(
            left: 12,
            top: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white24),
              ),
              child: Text(
                modeOverlay,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FacePainter extends CustomPainter {
  _FacePainter({
    required this.face,
    required this.identityLabel,
    required this.identityConfidence,
  });

  final Insta360LinkFaceEvent? face;
  final String? identityLabel;
  final double? identityConfidence;

  @override
  void paint(Canvas canvas, Size size) {
    if (face == null) {
      return;
    }
    final double x = face!.x;
    final double y = face!.y;
    final double w = face!.w;
    final double h = face!.h;
    final Rect rect = Rect.fromLTWH(
      x * size.width,
      y * size.height,
      w * size.width,
      h * size.height,
    );
    final Paint paint = Paint()
      ..color = const Color(0xFF00E5FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawRect(rect, paint);
    final String? label = identityLabel;
    if (label == null || label.isEmpty) {
      return;
    }
    final String confidenceText = identityConfidence == null
        ? ""
        : " ${(identityConfidence!).toStringAsFixed(1)}%";
    final TextSpan span = TextSpan(
      text: "$label$confidenceText",
      style: const TextStyle(
        color: Colors.white,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    );
    final TextPainter textPainter = TextPainter(
      text: span,
      textDirection: TextDirection.ltr,
    )..layout();
    final double pad = 6;
    final double boxWidth = textPainter.width + pad * 2;
    final double boxHeight = textPainter.height + pad * 2;
    final Offset labelOffset = Offset(
      rect.left,
      (rect.top - boxHeight - 6).clamp(0.0, size.height - boxHeight),
    );
    final RRect bg = RRect.fromRectAndRadius(
      Rect.fromLTWH(labelOffset.dx, labelOffset.dy, boxWidth, boxHeight),
      const Radius.circular(6),
    );
    final Paint bgPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.6);
    canvas.drawRRect(bg, bgPaint);
    textPainter.paint(
      canvas,
      Offset(labelOffset.dx + pad, labelOffset.dy + pad),
    );
  }

  @override
  bool shouldRepaint(covariant _FacePainter oldDelegate) =>
      oldDelegate.face != face ||
      oldDelegate.identityLabel != identityLabel ||
      oldDelegate.identityConfidence != identityConfidence;
}

class _GimbalCard extends StatelessWidget {
  const _GimbalCard({
    required this.onMove,
    required this.onZoom,
    required this.mode,
    required this.onAutomatic,
    required this.onManual,
  });

  final Future<void> Function(double pan, double tilt) onMove;
  final Future<void> Function(double zoom) onZoom;
  final _ControlMode mode;
  final Future<void> Function() onAutomatic;
  final Future<void> Function() onManual;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton(
                    onPressed: mode == _ControlMode.automatic
                        ? null
                        : onAutomatic,
                    child: const Text("Automatic"),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: mode == _ControlMode.manual ? null : onManual,
                    child: const Text("Manual"),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                const Spacer(),
                SizedBox(
                  width: 72,
                  child: OutlinedButton(
                    onPressed: () => onMove(0, 1),
                    child: const Icon(Icons.keyboard_arrow_up),
                  ),
                ),
                const Spacer(),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                SizedBox(
                  width: 72,
                  child: OutlinedButton(
                    onPressed: () => onMove(-1, 0),
                    child: const Icon(Icons.keyboard_arrow_left),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 72,
                  child: OutlinedButton(
                    onPressed: () => onMove(0, 0),
                    child: const Icon(Icons.gps_fixed),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 72,
                  child: OutlinedButton(
                    onPressed: () => onMove(1, 0),
                    child: const Icon(Icons.keyboard_arrow_right),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                SizedBox(
                  width: 72,
                  child: OutlinedButton(
                    onPressed: () => onZoom(1),
                    child: const Icon(Icons.zoom_in),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 72,
                  child: OutlinedButton(
                    onPressed: () => onMove(0, -1),
                    child: const Icon(Icons.keyboard_arrow_down),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 72,
                  child: OutlinedButton(
                    onPressed: () => onZoom(-1),
                    child: const Icon(Icons.zoom_out),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.fps,
    required this.latencyMs,
    required this.pan,
    required this.tilt,
    required this.connectedDeviceName,
    required this.totalDevices,
    required this.uvcDevices,
    required this.streamSource,
    required this.streamKbps,
    required this.streamPackets,
    required this.streamFrames,
    required this.streamBytes,
    required this.onRecoverPreview,
    required this.onDumpPreview,
  });

  final double fps;
  final double latencyMs;
  final double pan;
  final double tilt;
  final String connectedDeviceName;
  final int totalDevices;
  final int uvcDevices;
  final String streamSource;
  final double streamKbps;
  final int streamPackets;
  final int streamFrames;
  final int streamBytes;
  final Future<void> Function() onRecoverPreview;
  final Future<void> Function() onDumpPreview;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text("Status", style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text(
              "Telemetry",
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text("FPS: ${fps.toStringAsFixed(1)}"),
            Text("Latency: ${latencyMs.toStringAsFixed(1)} ms"),
            Text("Pan: ${pan.toStringAsFixed(2)}"),
            Text("Tilt: ${tilt.toStringAsFixed(2)}"),
            const SizedBox(height: 10),
            const Text("USB", style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text("Connected: $connectedDeviceName"),
            Text("USB devices: $totalDevices (UVC: $uvcDevices)"),
            Text("Stream source: $streamSource"),
            Text("Stream: ${streamKbps.toStringAsFixed(1)} kb/s"),
            Text("Packets: $streamPackets  Frames: $streamFrames"),
            Text("Bytes/s: $streamBytes"),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: onRecoverPreview,
              icon: const Icon(Icons.refresh),
              label: const Text("Try Recovery"),
            ),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              onPressed: onDumpPreview,
              icon: const Icon(Icons.camera_alt_outlined),
              label: const Text("Dump Preview"),
            ),
          ],
        ),
      ),
    );
  }
}

class _PidCard extends StatelessWidget {
  const _PidCard({
    required this.kpX,
    required this.kiX,
    required this.kdX,
    required this.kpY,
    required this.kiY,
    required this.kdY,
    required this.onChanged,
  });

  final double kpX;
  final double kiX;
  final double kdX;
  final double kpY;
  final double kiY;
  final double kdY;
  final void Function(
    double kpX,
    double kiX,
    double kdX,
    double kpY,
    double kiY,
    double kdY,
  )
  onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              "PID Tuning",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _PidSlider(
              label: "Kp X",
              value: kpX,
              min: -2.0,
              max: 2.0,
              onChanged: (double v) => onChanged(v, kiX, kdX, kpY, kiY, kdY),
            ),
            _PidSlider(
              label: "Ki X",
              value: kiX,
              min: -0.5,
              max: 0.5,
              onChanged: (double v) => onChanged(kpX, v, kdX, kpY, kiY, kdY),
            ),
            _PidSlider(
              label: "Kd X",
              value: kdX,
              min: -1.0,
              max: 1.0,
              onChanged: (double v) => onChanged(kpX, kiX, v, kpY, kiY, kdY),
            ),
            _PidSlider(
              label: "Kp Y",
              value: kpY,
              min: -2.0,
              max: 2.0,
              onChanged: (double v) => onChanged(kpX, kiX, kdX, v, kiY, kdY),
            ),
            _PidSlider(
              label: "Ki Y",
              value: kiY,
              min: -0.5,
              max: 0.5,
              onChanged: (double v) => onChanged(kpX, kiX, kdX, kpY, v, kdY),
            ),
            _PidSlider(
              label: "Kd Y",
              value: kdY,
              min: -1.0,
              max: 1.0,
              onChanged: (double v) => onChanged(kpX, kiX, kdX, kpY, kiY, v),
            ),
          ],
        ),
      ),
    );
  }
}

class _InitCard extends StatelessWidget {
  const _InitCard({
    required this.status,
    required this.message,
    required this.devices,
    required this.onInit,
    required this.onRefresh,
    required this.onReconnect,
    required this.onConnectFirst,
    required this.onActivateCamera,
    required this.onStartTracking,
    required this.onStopTracking,
    required this.onRecoverPreview,
  });

  final String status;
  final String message;
  final List<Insta360LinkDeviceInfo> devices;
  final Future<void> Function() onInit;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onReconnect;
  final Future<void> Function() onConnectFirst;
  final Future<void> Function() onActivateCamera;
  final Future<void> Function() onStartTracking;
  final Future<void> Function() onStopTracking;
  final Future<void> Function() onRecoverPreview;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text(
              "Initialization",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text("Status: $status"),
            Text(message),
            const SizedBox(height: 10),
            FilledButton(onPressed: onInit, child: const Text("Initialize")),
            const SizedBox(height: 6),
            OutlinedButton(
              onPressed: onRefresh,
              child: const Text("Refresh USB Devices"),
            ),
            const SizedBox(height: 6),
            OutlinedButton(
              onPressed: onReconnect,
              child: const Text("Reconnect Last Device"),
            ),
            const SizedBox(height: 6),
            OutlinedButton(
              onPressed: onConnectFirst,
              child: const Text("Connect First UVC Device"),
            ),
            const SizedBox(height: 6),
            OutlinedButton(
              onPressed: onActivateCamera,
              child: const Text("Activate Camera Stream"),
            ),
            const SizedBox(height: 6),
            OutlinedButton(
              onPressed: onRecoverPreview,
              child: const Text("Recover Preview (Init→Connect→Activate)"),
            ),
            const SizedBox(height: 6),
            FilledButton(
              onPressed: onStartTracking,
              child: const Text("Start Tracking"),
            ),
            const SizedBox(height: 6),
            OutlinedButton(
              onPressed: onStopTracking,
              child: const Text("Stop Tracking"),
            ),
            const SizedBox(height: 10),
            const Text(
              "USB Devices",
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            if (devices.isEmpty)
              const Text("No devices listed.")
            else
              ...devices.map((Insta360LinkDeviceInfo d) {
                final String name = d.name;
                final int vid = d.vid;
                final int pid = d.pid;
                final bool uvc = d.isUvc;
                final bool perm = d.hasPermission;
                return Text(
                  "$name vid=0x${vid.toRadixString(16)} pid=0x${pid.toRadixString(16)} "
                  "uvc=$uvc perm=$perm",
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _PersonGroup {
  const _PersonGroup({required this.name, required this.faces});

  final String name;
  final List<FacePerson> faces;

  String get displayName => name.isEmpty ? "Unnamed" : name;
}

class _IdentityMatch {
  const _IdentityMatch({required this.name, required this.score});

  final String name;
  final double score;
}

class _PeopleTab extends StatelessWidget {
  const _PeopleTab({
    required this.people,
    required this.onOpenPerson,
    required this.onEnroll,
    required this.nameController,
  });

  final List<FacePerson> people;
  final void Function(_PersonGroup group) onOpenPerson;
  final Future<void> Function(String name) onEnroll;
  final TextEditingController nameController;

  List<_PersonGroup> _groupPeople() {
    final Map<String, List<FacePerson>> grouped = <String, List<FacePerson>>{};
    for (final FacePerson person in people) {
      grouped.putIfAbsent(person.name, () => <FacePerson>[]).add(person);
    }
    final List<_PersonGroup> groups = grouped.entries.map((
      MapEntry<String, List<FacePerson>> entry,
    ) {
      entry.value.sort(
        (FacePerson a, FacePerson b) => b.createdAt.compareTo(a.createdAt),
      );
      return _PersonGroup(name: entry.key, faces: entry.value);
    }).toList();
    groups.sort(
      (_PersonGroup a, _PersonGroup b) =>
          b.faces.first.createdAt.compareTo(a.faces.first.createdAt),
    );
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final List<_PersonGroup> groups = _groupPeople();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text("People", style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.black12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Text(
                    "Enroll current face",
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: "Person name",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: () => onEnroll(nameController.text),
                    child: const Text("Enroll from current face"),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              "Known people",
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            if (groups.isEmpty)
              const Text("No people enrolled yet.")
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: groups.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (BuildContext context, int index) {
                  final _PersonGroup group = groups[index];
                  final FacePerson cover = group.faces.first;
                  return InkWell(
                    onTap: () => onOpenPerson(group),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: Colors.black.withValues(alpha: 0.03),
                        border: Border.all(color: Colors.black12),
                      ),
                      child: Row(
                        children: <Widget>[
                          _PersonFaceThumb(bytes: cover.faceJpegBytes),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  group.displayName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  "${group.faces.length} face${group.faces.length == 1 ? "" : "s"}",
                                  style: const TextStyle(color: Colors.black54),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _SettingsTab extends StatelessWidget {
  const _SettingsTab({
    required this.kpX,
    required this.kiX,
    required this.kdX,
    required this.kpY,
    required this.kiY,
    required this.kdY,
    required this.onPidChanged,
    required this.serverUrl,
    required this.urlController,
    required this.onSaveServerUrl,
  });

  final double kpX;
  final double kiX;
  final double kdX;
  final double kpY;
  final double kiY;
  final double kdY;
  final void Function(
    double kpX,
    double kiX,
    double kdX,
    double kpY,
    double kiY,
    double kdY,
  )
  onPidChanged;
  final String serverUrl;
  final TextEditingController urlController;
  final Future<void> Function(String url) onSaveServerUrl;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text(
              "Settings",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            _PidCard(
              kpX: kpX,
              kiX: kiX,
              kdX: kdX,
              kpY: kpY,
              kiY: kiY,
              kdY: kdY,
              onChanged: onPidChanged,
            ),
            const SizedBox(height: 12),
            const Text(
              "Recognition server",
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: urlController,
              decoration: const InputDecoration(
                labelText: "Server URL (e.g. https://host/api)",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 6),
            OutlinedButton(
              onPressed: () => onSaveServerUrl(urlController.text),
              child: Text(
                serverUrl.isEmpty ? "Save server URL" : "Update server URL",
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PersonFaceThumb extends StatelessWidget {
  const _PersonFaceThumb({required this.bytes});

  final List<int>? bytes;

  @override
  Widget build(BuildContext context) {
    if (bytes == null || bytes!.isEmpty) {
      return Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: Colors.black12,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.person, color: Colors.black45),
      );
    }
    final Uint8List data = Uint8List.fromList(bytes!);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.memory(
        data,
        width: 56,
        height: 56,
        fit: BoxFit.cover,
        gaplessPlayback: true,
      ),
    );
  }
}

class _PersonDetailPage extends StatefulWidget {
  const _PersonDetailPage({
    required this.isar,
    required this.initialName,
    required this.initialFaces,
  });

  final IsarService isar;
  final String initialName;
  final List<FacePerson> initialFaces;

  @override
  State<_PersonDetailPage> createState() => _PersonDetailPageState();
}

class _PersonDetailPageState extends State<_PersonDetailPage> {
  late final TextEditingController _nameController;
  late String _currentName;
  List<FacePerson> _faces = <FacePerson>[];

  @override
  void initState() {
    super.initState();
    _currentName = widget.initialName;
    _nameController = TextEditingController(text: _currentName);
    _faces = List<FacePerson>.from(widget.initialFaces);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  String get _displayName => _currentName.isEmpty ? "Unnamed" : _currentName;

  Future<void> _reloadFaces() async {
    final faces = await widget.isar.listPeopleByName(_currentName);
    if (!mounted) {
      return;
    }
    setState(() {
      _faces = faces;
    });
  }

  Future<void> _saveName() async {
    final String next = _nameController.text.trim();
    if (next == _currentName) {
      return;
    }
    await widget.isar.renamePeople(_currentName, next);
    if (!mounted) {
      return;
    }
    setState(() {
      _currentName = next;
    });
    await _reloadFaces();
  }

  Future<void> _deleteFace(FacePerson face) async {
    await widget.isar.deletePerson(face.id);
    await _reloadFaces();
  }

  Future<void> _deleteAllFaces() async {
    await widget.isar.deletePeopleByName(_currentName);
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_displayName)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      const Text(
                        "Person",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: "Name",
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      FilledButton(
                        onPressed: _saveName,
                        child: const Text("Save name"),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  const Text(
                    "Faces",
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  Text(
                    "${_faces.length}",
                    style: const TextStyle(color: Colors.black54),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_faces.isEmpty)
                const Text("No faces captured yet.")
              else
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _faces.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 1,
                  ),
                  itemBuilder: (BuildContext context, int index) {
                    final FacePerson face = _faces[index];
                    return _FaceTile(
                      bytes: face.faceJpegBytes,
                      onDelete: () => _deleteFace(face),
                    );
                  },
                ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: _deleteAllFaces,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                child: const Text("Delete person"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FaceTile extends StatelessWidget {
  const _FaceTile({required this.bytes, required this.onDelete});

  final List<int>? bytes;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final Widget image = bytes == null || bytes!.isEmpty
        ? Container(
            color: Colors.black12,
            child: const Center(
              child: Icon(Icons.person, color: Colors.black45),
            ),
          )
        : Image.memory(
            Uint8List.fromList(bytes!),
            fit: BoxFit.cover,
            gaplessPlayback: true,
          );
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          image,
          Positioned(
            top: 6,
            right: 6,
            child: IconButton(
              onPressed: onDelete,
              style: IconButton.styleFrom(
                backgroundColor: Colors.black.withValues(alpha: 0.6),
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.delete, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}

class _PidSlider extends StatelessWidget {
  const _PidSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        SizedBox(width: 42, child: Text(label)),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: 100,
            label: value.toStringAsFixed(4),
            onChanged: onChanged,
          ),
        ),
        SizedBox(width: 56, child: Text(value.toStringAsFixed(4))),
      ],
    );
  }
}
