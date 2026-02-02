import "dart:async";
import "dart:typed_data";

import "package:flutter/material.dart";

import "insta_link_tracker.dart";

enum _ControlMode { automatic, manual }

class TrackingPage extends StatefulWidget {
  const TrackingPage({super.key});

  @override
  State<TrackingPage> createState() => _TrackingPageState();
}

class _TrackingPageState extends State<TrackingPage> {
  final InstaLinkTracker _tracker = InstaLinkTracker();

  StreamSubscription<Map<String, dynamic>>? _eventSub;
  Timer? _previewTimer;
  List<Map<String, dynamic>> _devices = <Map<String, dynamic>>[];
  String _status = "idle";
  String _message = "Press Initialize to start.";
  bool _isRunning = false;
  _ControlMode _mode = _ControlMode.automatic;
  int _lastGimbalCmdMs = 0;

  double _fps = 0;
  double _latencyMs = 0;
  double _pan = 0;
  double _tilt = 0;
  Map<String, dynamic>? _face;
  double _streamKbps = 0;
  int _streamPackets = 0;
  int _streamFrames = 0;
  int _streamBytes = 0;
  String _streamSource = "uvc";
  String _connectedDeviceName = "-";
  Uint8List? _previewJpeg;

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
    unawaited(_autoBootstrap());
  }

  @override
  void dispose() {
    _previewTimer?.cancel();
    _eventSub?.cancel();
    _tracker.dispose();
    super.dispose();
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

  void _onEvent(Map<String, dynamic> event) {
    final String type = (event["type"] ?? "").toString();
    if (!mounted) {
      return;
    }
    setState(() {
      if (type == "state") {
        _status = (event["status"] ?? _status).toString();
        _message = (event["message"] ?? _message).toString();
        _isRunning = _status == "running";
        if (_isRunning) {
          _mode = _ControlMode.automatic;
        }
      } else if (type == "telemetry") {
        _fps = _asDouble(event["fps"], _fps);
        _latencyMs = _asDouble(event["latencyMs"], _latencyMs);
        _pan = _asDouble(event["pan"], _pan);
        _tilt = _asDouble(event["tilt"], _tilt);
      } else if (type == "face") {
        _face = event;
      } else if (type == "stream") {
        _streamKbps = _asDouble(event["kbps"], _streamKbps);
        _streamPackets = (event["packets"] as num?)?.toInt() ?? _streamPackets;
        _streamFrames = (event["frames"] as num?)?.toInt() ?? _streamFrames;
        _streamBytes = (event["bytes"] as num?)?.toInt() ?? _streamBytes;
        _streamSource = (event["source"] ?? _streamSource).toString();
      }
    });
    if (type == "telemetry" &&
        _mode == _ControlMode.automatic &&
        !(event["source"] ?? "").toString().startsWith("yolov8n-face-tflite")) {
      unawaited(_maybeSendTrackingGimbal(_pan, _tilt, _fps));
    }
  }

  Future<void> _maybeSendTrackingGimbal(
    double pan,
    double tilt,
    double fps,
  ) async {
    if (!_isRunning || _mode != _ControlMode.automatic || fps <= 0) {
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
    await _tracker.manualControl(
      pan: panCmd,
      tilt: tiltCmd,
      durationMs: 200,
    );
  }

  double _asDouble(dynamic value, double fallback) {
    if (value is num) {
      return value.toDouble();
    }
    return fallback;
  }

  Future<void> _refreshDevices() async {
    final List<Map<String, dynamic>> devices = await _tracker.listDevices();
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
    await _refreshDevices();
    final bool connected = await _connectFirstDevice(silent: true);
    if (!connected) {
      setState(() {
        _status = "error";
        _message = "Auto connect failed. Check USB/hub, then use Reconnect.";
      });
      return;
    }
    final bool started = await _startTracking(silent: true);
    setState(() {
      _mode = _ControlMode.automatic;
      _status = started ? "running" : "error";
      _isRunning = started;
      _message = started ? "Automatic tracking active." : "Auto start failed.";
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
    final Map<String, dynamic>? first = _devices
        .cast<Map<String, dynamic>?>()
        .firstWhere(
          (Map<String, dynamic>? d) => (d?["isUvc"] == true),
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
      vid: (first["vid"] as num?)?.toInt() ?? 0,
      pid: (first["pid"] as num?)?.toInt() ?? 0,
    );
    if (!silent) {
      setState(() {
        _connectedDeviceName = (first["name"] ?? "-").toString();
        _status = ok ? "connected" : "error";
        _message = ok
            ? "Connected to ${first["name"] ?? "device"}."
            : "Connect failed.";
      });
    } else if (ok) {
      _connectedDeviceName = (first["name"] ?? "-").toString();
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
    final bool ok = await _tracker.startTracking();
    if (!silent) {
      setState(() {
        _status = ok ? "running" : "error";
        _isRunning = ok;
        _mode = ok ? _ControlMode.automatic : _mode;
        _message = ok ? "Automatic tracking active." : "Start failed.";
      });
    }
    return ok;
  }

  Future<bool> _stopTracking({bool silent = false}) async {
    final bool ok = await _tracker.stopTracking();
    if (!silent) {
      setState(() {
        _status = ok ? "connected" : "error";
        _isRunning = false;
        _message = ok ? "Tracking stopped." : "Stop failed.";
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
    if (_isRunning) {
      await _stopTracking(silent: true);
    }
    setState(() {
      _mode = _ControlMode.manual;
      _isRunning = false;
      _status = "connected";
      _message = "Manual mode active. Press Automatic to resume face tracking.";
    });
  }

  Future<void> _manualZoom(double zoom) async {
    await _enterManualMode();
    final bool ok = await _tracker.manualZoom(zoom: zoom, durationMs: 350);
    setState(() {
      _message = ok ? "Manual zoom ${zoom > 0 ? "in" : "out"}" : "Manual zoom failed.";
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              child: Row(
                children: <Widget>[
                  Expanded(child: _PreviewCard(face: _face, jpegFrame: _previewJpeg)),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 340,
                    child: Column(
                      children: <Widget>[
                        Expanded(
                          child: DefaultTabController(
                            length: 4,
                            child: Column(
                              children: <Widget>[
                                const TabBar(
                                  isScrollable: true,
                                  tabs: <Widget>[
                                    Tab(text: "Gimbal"),
                                    Tab(text: "Telemetry"),
                                    Tab(text: "USB"),
                                    Tab(text: "PID"),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Expanded(
                                  child: TabBarView(
                                    children: <Widget>[
                                      SingleChildScrollView(
                                        child: _GimbalCard(
                                          onMove: _manualMove,
                                          onZoom: _manualZoom,
                                          mode: _mode,
                                          onAutomatic: _setAutomaticMode,
                                          onManual: _enterManualMode,
                                        ),
                                      ),
                                      SingleChildScrollView(
                                        child: _TelemetryCard(
                                          fps: _fps,
                                          latencyMs: _latencyMs,
                                          pan: _pan,
                                          tilt: _tilt,
                                        ),
                                      ),
                                      SingleChildScrollView(
                                        child: _UsbHealthCard(
                                          connectedDeviceName: _connectedDeviceName,
                                          totalDevices: _devices.length,
                                          uvcDevices: _devices
                                              .where(
                                                (Map<String, dynamic> d) => d["isUvc"] == true,
                                              )
                                              .length,
                                          streamSource: _streamSource,
                                          streamKbps: _streamKbps,
                                          streamPackets: _streamPackets,
                                          streamFrames: _streamFrames,
                                          streamBytes: _streamBytes,
                                        ),
                                      ),
                                      SingleChildScrollView(
                                        child: _PidCard(
                                          kpX: _kpX,
                                          kiX: _kiX,
                                          kdX: _kdX,
                                          kpY: _kpY,
                                          kiY: _kiY,
                                          kdY: _kdY,
                                          onChanged:
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
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.face, required this.jpegFrame});

  final Map<String, dynamic>? face;
  final Uint8List? jpegFrame;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Container(color: Colors.black),
            if (jpegFrame != null)
              Image.memory(
                jpegFrame!,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              )
            else
              const Center(
                child: Text(
                  "Waiting preview frame...",
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            CustomPaint(painter: _FacePainter(face: face)),
          ],
        ),
      ),
    );
  }
}

class _FacePainter extends CustomPainter {
  _FacePainter({required this.face});

  final Map<String, dynamic>? face;

  @override
  void paint(Canvas canvas, Size size) {
    if (face == null) {
      return;
    }
    final double x = (face!["x"] as num?)?.toDouble() ?? 0.4;
    final double y = (face!["y"] as num?)?.toDouble() ?? 0.3;
    final double w = (face!["w"] as num?)?.toDouble() ?? 0.2;
    final double h = (face!["h"] as num?)?.toDouble() ?? 0.25;
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
  }

  @override
  bool shouldRepaint(covariant _FacePainter oldDelegate) =>
      oldDelegate.face != face;
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
                    onPressed: mode == _ControlMode.automatic ? null : onAutomatic,
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
            const SizedBox(height: 4),
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

class _TelemetryCard extends StatelessWidget {
  const _TelemetryCard({
    required this.fps,
    required this.latencyMs,
    required this.pan,
    required this.tilt,
  });

  final double fps;
  final double latencyMs;
  final double pan;
  final double tilt;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              "Telemetry",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text("FPS: ${fps.toStringAsFixed(1)}"),
            Text("Latency: ${latencyMs.toStringAsFixed(1)} ms"),
            Text("Pan: ${pan.toStringAsFixed(2)}"),
            Text("Tilt: ${tilt.toStringAsFixed(2)}"),
          ],
        ),
      ),
    );
  }
}

class _UsbHealthCard extends StatelessWidget {
  const _UsbHealthCard({
    required this.connectedDeviceName,
    required this.totalDevices,
    required this.uvcDevices,
    required this.streamSource,
    required this.streamKbps,
    required this.streamPackets,
    required this.streamFrames,
    required this.streamBytes,
  });

  final String connectedDeviceName;
  final int totalDevices;
  final int uvcDevices;
  final String streamSource;
  final double streamKbps;
  final int streamPackets;
  final int streamFrames;
  final int streamBytes;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              "USB Health",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text("Connected: $connectedDeviceName"),
            Text("USB devices: $totalDevices (UVC: $uvcDevices)"),
            Text("Stream source: $streamSource"),
            Text("Stream: ${streamKbps.toStringAsFixed(1)} kb/s"),
            Text("Packets: $streamPackets  Frames: $streamFrames"),
            Text("Bytes/s: $streamBytes"),
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
