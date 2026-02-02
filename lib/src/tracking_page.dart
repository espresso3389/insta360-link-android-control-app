import "dart:async";

import "package:flutter/material.dart";

import "insta_link_tracker.dart";

class TrackingPage extends StatefulWidget {
  const TrackingPage({super.key});

  @override
  State<TrackingPage> createState() => _TrackingPageState();
}

class _TrackingPageState extends State<TrackingPage> {
  final InstaLinkTracker _tracker = InstaLinkTracker();

  StreamSubscription<Map<String, dynamic>>? _eventSub;
  List<Map<String, dynamic>> _devices = <Map<String, dynamic>>[];
  String _status = "idle";
  String _message = "Press Initialize to start.";
  bool _isRunning = false;

  double _fps = 0;
  double _latencyMs = 0;
  double _pan = 0;
  double _tilt = 0;
  Map<String, dynamic>? _face;

  double _kpX = 0.015;
  double _kiX = 0;
  double _kdX = 0.004;
  double _kpY = 0.015;
  double _kiY = 0;
  double _kdY = 0.004;

  @override
  void initState() {
    super.initState();
    _eventSub = _tracker.events.listen(_onEvent);
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _tracker.dispose();
    super.dispose();
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
      } else if (type == "telemetry") {
        _fps = _asDouble(event["fps"], _fps);
        _latencyMs = _asDouble(event["latencyMs"], _latencyMs);
        _pan = _asDouble(event["pan"], _pan);
        _tilt = _asDouble(event["tilt"], _tilt);
      } else if (type == "face") {
        _face = event;
      }
    });
  }

  double _asDouble(dynamic value, double fallback) {
    if (value is num) {
      return value.toDouble();
    }
    return fallback;
  }

  Future<void> _initialize() async {
    final bool ok = await _tracker.init();
    if (!ok) {
      setState(() {
        _status = "error";
        _message = "Native init failed.";
      });
      return;
    }
    final List<Map<String, dynamic>> devices = await _tracker.listDevices();
    setState(() {
      _devices = devices;
      _status = "ready";
      _message = devices.isEmpty
          ? "No UVC devices found."
          : "Found ${devices.length} UVC device(s).";
    });
  }

  Future<void> _connectFirstDevice() async {
    if (_devices.isEmpty) {
      return;
    }
    final Map<String, dynamic> first = _devices.first;
    final bool ok = await _tracker.connectDevice(
      vid: (first["vid"] as num?)?.toInt() ?? 0,
      pid: (first["pid"] as num?)?.toInt() ?? 0,
    );
    setState(() {
      _status = ok ? "connected" : "error";
      _message = ok
          ? "Connected to ${first["name"] ?? "device"}."
          : "Connect failed.";
    });
  }

  Future<void> _startTracking() async {
    await _tracker.setPid(
      kpX: _kpX,
      kiX: _kiX,
      kdX: _kdX,
      kpY: _kpY,
      kiY: _kiY,
      kdY: _kdY,
    );
    final bool ok = await _tracker.startTracking();
    setState(() {
      _status = ok ? "running" : "error";
      _isRunning = ok;
      _message = ok ? "Tracking started." : "Start failed.";
    });
  }

  Future<void> _stopTracking() async {
    final bool ok = await _tracker.stopTracking();
    setState(() {
      _status = ok ? "connected" : "error";
      _isRunning = false;
      _message = ok ? "Tracking stopped." : "Stop failed.";
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text("Insta360 Link Face Tracker")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _StatusCard(status: _status, message: _message),
            const SizedBox(height: 12),
            Expanded(
              child: Row(
                children: <Widget>[
                  Expanded(child: _PreviewCard(face: _face)),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 320,
                    child: ListView(
                      children: <Widget>[
                        _ControlsCard(
                          onInitialize: _initialize,
                          onConnect: _connectFirstDevice,
                          onStart: _startTracking,
                          onStop: _stopTracking,
                          hasDevices: _devices.isNotEmpty,
                          running: _isRunning,
                        ),
                        const SizedBox(height: 12),
                        _TelemetryCard(
                          fps: _fps,
                          latencyMs: _latencyMs,
                          pan: _pan,
                          tilt: _tilt,
                        ),
                        const SizedBox(height: 12),
                        _PidCard(
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
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Tip: native layer currently emits mock telemetry. Replace with libuvc + YOLOv8n-face + gimbal controls.",
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.status, required this.message});

  final String status;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(
          status == "error" ? Icons.error_outline : Icons.usb_rounded,
          color: status == "error" ? Colors.red : null,
        ),
        title: Text("State: $status"),
        subtitle: Text(message),
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.face});

  final Map<String, dynamic>? face;

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
            const Center(
              child: Text(
                "Native UVC preview hook",
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

class _ControlsCard extends StatelessWidget {
  const _ControlsCard({
    required this.onInitialize,
    required this.onConnect,
    required this.onStart,
    required this.onStop,
    required this.hasDevices,
    required this.running,
  });

  final Future<void> Function() onInitialize;
  final Future<void> Function() onConnect;
  final Future<void> Function() onStart;
  final Future<void> Function() onStop;
  final bool hasDevices;
  final bool running;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text(
              "Controls",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: onInitialize,
              icon: const Icon(Icons.settings_input_hdmi_rounded),
              label: const Text("Initialize"),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: hasDevices ? onConnect : null,
              child: const Text("Connect First Device"),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: running ? null : onStart,
              child: const Text("Start Tracking"),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: running ? onStop : null,
              child: const Text("Stop Tracking"),
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
              max: 0.05,
              onChanged: (double v) => onChanged(v, kiX, kdX, kpY, kiY, kdY),
            ),
            _PidSlider(
              label: "Ki X",
              value: kiX,
              max: 0.01,
              onChanged: (double v) => onChanged(kpX, v, kdX, kpY, kiY, kdY),
            ),
            _PidSlider(
              label: "Kd X",
              value: kdX,
              max: 0.02,
              onChanged: (double v) => onChanged(kpX, kiX, v, kpY, kiY, kdY),
            ),
            _PidSlider(
              label: "Kp Y",
              value: kpY,
              max: 0.05,
              onChanged: (double v) => onChanged(kpX, kiX, kdX, v, kiY, kdY),
            ),
            _PidSlider(
              label: "Ki Y",
              value: kiY,
              max: 0.01,
              onChanged: (double v) => onChanged(kpX, kiX, kdX, kpY, v, kdY),
            ),
            _PidSlider(
              label: "Kd Y",
              value: kdY,
              max: 0.02,
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
    required this.max,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        SizedBox(width: 42, child: Text(label)),
        Expanded(
          child: Slider(
            value: value,
            min: 0,
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
