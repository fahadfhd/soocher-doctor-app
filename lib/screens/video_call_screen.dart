import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:stream_video_flutter/stream_video_flutter.dart';

import '../config/stream_config.dart';
import '../services/video_call_service.dart';

class VideoCallScreen extends StatefulWidget {
  const VideoCallScreen({
    super.key,
    required this.uid,
    required this.idToken,
    required this.consultationId,
  });

  final String uid;
  final String idToken;
  final String consultationId;

  @override
  State<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen>
    with TickerProviderStateMixin {
  static const _primary = Color(0xFF2E6DD4);

  String _status = 'Requesting permissions…';
  Call? _call;
  CallState? _callState;
  String? _error;
  String _patientName = 'Patient';
  bool _disposed = false;

  // Controls visibility
  bool _controlsVisible = true;
  Timer? _controlsTimer;

  // Mic / cam toggles
  bool _micOn = true;
  bool _camOn = true;

  // Call duration
  Timer? _durationTimer;
  int _seconds = 0;

  late final AnimationController _controlsFadeCtrl;
  late final Animation<double> _controlsFade;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarBrightness: Brightness.dark,
    ));
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _controlsFadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
      value: 1,
    );
    _controlsFade =
        CurvedAnimation(parent: _controlsFadeCtrl, curve: Curves.easeInOut);

    _initCall();
  }

  @override
  void dispose() {
    _disposed = true;
    _controlsTimer?.cancel();
    _durationTimer?.cancel();
    _controlsFadeCtrl.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _cleanUp();
    super.dispose();
  }

  Future<void> _cleanUp() async {
    try { await _call?.leave(); } catch (_) {}
    try { await StreamVideo.reset(disconnect: true); } catch (_) {}
  }

  void _safeSetState(VoidCallback fn) {
    if (!_disposed && mounted) setState(fn);
  }

  void _startControlsTimer() {
    _controlsTimer?.cancel();
    _controlsTimer = Timer(const Duration(seconds: 4), () {
      if (!_disposed && mounted) {
        _controlsFadeCtrl.reverse();
        setState(() => _controlsVisible = false);
      }
    });
  }

  void _toggleControls() {
    if (_controlsVisible) {
      _controlsTimer?.cancel();
      _controlsFadeCtrl.reverse();
      setState(() => _controlsVisible = false);
    } else {
      _controlsFadeCtrl.forward();
      setState(() => _controlsVisible = true);
      _startControlsTimer();
    }
  }

  void _showControls() {
    if (!_controlsVisible) {
      _controlsFadeCtrl.forward();
      setState(() => _controlsVisible = true);
    }
    _startControlsTimer();
  }

  String get _duration {
    final m = _seconds ~/ 60;
    final s = _seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _initCall() async {
    try {
      _safeSetState(() => _status = 'Requesting permissions…');
      final statuses =
          await [Permission.camera, Permission.microphone].request();
      final denied =
          statuses.values.any((s) => s.isDenied || s.isPermanentlyDenied);
      if (denied) throw Exception('Camera or microphone permission denied.');

      _safeSetState(() => _status = 'Fetching call details…');
      final data = await VideoCallService.resolve(
        uid: widget.uid,
        idToken: widget.idToken,
        consultationId: widget.consultationId,
      );
      _safeSetState(() => _patientName = data.patientName);

      _safeSetState(() => _status = 'Connecting…');
      if (StreamVideo.isInitialized()) await StreamVideo.reset(disconnect: true);

      StreamVideo(
        StreamConfig.apiKey,
        user: User.regular(
          userId: VideoCallService.sanitizeId(widget.uid),
          name: VideoCallService.sanitizeId(widget.uid),
        ),
        userToken: data.streamToken,
        failIfSingletonExists: false,
      );
      await StreamVideo.instance.connect();

      _safeSetState(() => _status = 'Joining call…');
      final call = StreamVideo.instance.makeCall(
        callType: StreamCallType.defaultType(),
        id: data.streamCallId,
      );

      await call.getOrCreate(memberIds: data.memberIds);
      call.connectOptions = CallConnectOptions(
        camera: TrackOption.enabled(),
        microphone: TrackOption.enabled(),
      );
      await call.join();

      call.state.listen((state) {
        _safeSetState(() => _callState = state);
        if (state.status is CallStatusDisconnected) {
          _safeSetState(() => _error = 'Call ended.');
        }
      });

      _safeSetState(() {
        _call = call;
        _callState = call.state.valueOrNull;
      });

      // Start duration counter and auto-hide controls
      _durationTimer =
          Timer.periodic(const Duration(seconds: 1), (_) {
        _safeSetState(() => _seconds++);
      });
      _startControlsTimer();
    } catch (e) {
      _safeSetState(
          () => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _leaveCall() async {
    await _cleanUp();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _toggleMic() async {
    await _call?.setMicrophoneEnabled(enabled: !_micOn);
    _safeSetState(() => _micOn = !_micOn);
    _showControls();
  }

  Future<void> _toggleCam() async {
    await _call?.setCameraEnabled(enabled: !_camOn);
    _safeSetState(() => _camOn = !_camOn);
    _showControls();
  }

  Future<void> _flipCamera() async {
    await _call?.flipCamera();
    _showControls();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111827),
      body: _error != null
          ? _ErrorView(error: _error!, onBack: _leaveCall)
          : _call == null || _callState == null
              ? _ConnectingView(status: _status, patientName: _patientName)
              : _ActiveCallView(
                  call: _call!,
                  callState: _callState!,
                  patientName: _patientName,
                  duration: _duration,
                  controlsVisible: _controlsVisible,
                  controlsFade: _controlsFade,
                  micOn: _micOn,
                  camOn: _camOn,
                  onTap: _toggleControls,
                  onMic: _toggleMic,
                  onCam: _toggleCam,
                  onFlip: _flipCamera,
                  onHangUp: _leaveCall,
                ),
    );
  }
}

// ── Active call ─────────────────────────────────────────────────────────────

class _ActiveCallView extends StatelessWidget {
  const _ActiveCallView({
    required this.call,
    required this.callState,
    required this.patientName,
    required this.duration,
    required this.controlsVisible,
    required this.controlsFade,
    required this.micOn,
    required this.camOn,
    required this.onTap,
    required this.onMic,
    required this.onCam,
    required this.onFlip,
    required this.onHangUp,
  });

  final Call call;
  final CallState callState;
  final String patientName;
  final String duration;
  final bool controlsVisible;
  final Animation<double> controlsFade;
  final bool micOn;
  final bool camOn;
  final VoidCallback onTap;
  final VoidCallback onMic;
  final VoidCallback onCam;
  final VoidCallback onFlip;
  final VoidCallback onHangUp;

  static const _primary = Color(0xFF2E6DD4);

  @override
  Widget build(BuildContext context) {
    final remote = callState.otherParticipants.firstOrNull;
    final local = callState.localParticipant;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ── Remote participant full screen ────────────────────────────
          if (remote != null)
            StreamCallParticipant(
              call: call,
              participant: remote,
              videoFit: VideoFit.cover,
              backgroundColor: const Color(0xFF111827),
              showParticipantLabel: false,
              showSpeakerBorder: false,
              showConnectionQualityIndicator: false,
              videoPlaceholderBuilder: (context, call, participant) =>
                  _VideoOffPlaceholder(name: patientName),
            )
          else
            _WaitingScreen(patientName: patientName),

          // ── Top gradient + header ─────────────────────────────────────
          FadeTransition(
            opacity: controlsFade,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xCC000000), Colors.transparent],
                  stops: [0.0, 0.35],
                ),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 12),
                  child: Row(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            patientName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF4ADE80),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                duration,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const Spacer(),
                      // Flip camera button
                      _GlassButton(
                        icon: Icons.flip_camera_ios_rounded,
                        onTap: onFlip,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── Local video PiP ───────────────────────────────────────────
          if (local != null)
            StreamLocalVideo(
              call: call,
              participant: local,
              localVideoWidth: 100,
              localVideoHeight: 150,
              localVideoPadding: 16,
              initialAlignment: FloatingViewAlignment.topRight,
              enableSnappingBehavior: true,
              borderRadius: BorderRadius.circular(16),
              shadowColor: Colors.black54,
              participantBuilder: (context, call, participant) =>
                  StreamCallParticipant(
                    call: call,
                    participant: participant,
                    borderRadius: BorderRadius.circular(16),
                    showParticipantLabel: false,
                    showSpeakerBorder: false,
                    showConnectionQualityIndicator: false,
                    videoPlaceholderBuilder: (context, call, participant) =>
                        const _VideoOffPlaceholder(name: 'You'),
                  ),
              child: const SizedBox.expand(),
            ),

          // ── Bottom gradient + controls ────────────────────────────────
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: FadeTransition(
              opacity: controlsFade,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Color(0xEE000000), Colors.transparent],
                    stops: [0.0, 0.7],
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(32, 40, 32, 48),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Mic
                    _ControlButton(
                      icon: micOn
                          ? Icons.mic_rounded
                          : Icons.mic_off_rounded,
                      label: micOn ? 'Mute' : 'Unmute',
                      active: micOn,
                      onTap: onMic,
                    ),
                    // Hang up
                    _HangUpButton(onTap: onHangUp),
                    // Camera
                    _ControlButton(
                      icon: camOn
                          ? Icons.videocam_rounded
                          : Icons.videocam_off_rounded,
                      label: camOn ? 'Camera' : 'No cam',
                      active: camOn,
                      onTap: onCam,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Video-off placeholder ────────────────────────────────────────────────────

class _VideoOffPlaceholder extends StatelessWidget {
  const _VideoOffPlaceholder({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1A2235),
      child: Center(
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: const Color(0xFF2E6DD4).withValues(alpha: 0.2),
            shape: BoxShape.circle,
            border: Border.all(
              color: const Color(0xFF2E6DD4).withValues(alpha: 0.4),
              width: 1.5,
            ),
          ),
          child: const Icon(
            Icons.person_rounded,
            color: Color(0xFF5A94FF),
            size: 38,
          ),
        ),
      ),
    );
  }
}

// ── Waiting for patient ──────────────────────────────────────────────────────

class _WaitingScreen extends StatelessWidget {
  const _WaitingScreen({required this.patientName});
  final String patientName;

  String get _initials {
    final parts = patientName.trim().split(' ');
    return parts.take(2).map((p) => p.isEmpty ? '' : p[0].toUpperCase()).join();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.center,
          radius: 1.2,
          colors: [Color(0xFF1E3A6E), Color(0xFF0A1628)],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFF5A94FF), Color(0xFF2E6DD4)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF2E6DD4).withValues(alpha: 0.5),
                    blurRadius: 40,
                    spreadRadius: 8,
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Text(
                _initials,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              patientName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Waiting for patient to join…',
              style: TextStyle(color: Colors.white54, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Control buttons ──────────────────────────────────────────────────────────

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: active
                  ? Colors.white.withValues(alpha: 0.18)
                  : Colors.white.withValues(alpha: 0.08),
              shape: BoxShape.circle,
              border: Border.all(
                color: active
                    ? Colors.white.withValues(alpha: 0.3)
                    : Colors.white.withValues(alpha: 0.1),
                width: 1.5,
              ),
            ),
            child: Icon(
              icon,
              color: active ? Colors.white : Colors.white38,
              size: 26,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: active ? Colors.white70 : Colors.white38,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _HangUpButton extends StatelessWidget {
  const _HangUpButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 70,
            height: 70,
            decoration: const BoxDecoration(
              color: Color(0xFFFF3B30),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Color(0x66FF3B30),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Icon(
              Icons.call_end_rounded,
              color: Colors.white,
              size: 30,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'End',
            style: TextStyle(
              color: Color(0xFFFF3B30),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassButton extends StatelessWidget {
  const _GlassButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          shape: BoxShape.circle,
          border: Border.all(
              color: Colors.white.withValues(alpha: 0.2), width: 1),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}

// ── Connecting screen ────────────────────────────────────────────────────────

class _ConnectingView extends StatelessWidget {
  const _ConnectingView(
      {required this.status, required this.patientName});
  final String status;
  final String patientName;

  String get _initials {
    final parts = patientName.trim().split(' ');
    return parts.take(2).map((p) => p.isEmpty ? '' : p[0].toUpperCase()).join();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.center,
          radius: 1.2,
          colors: [Color(0xFF1E3A6E), Color(0xFF0A1628)],
        ),
      ),
      child: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFF5A94FF), Color(0xFF2E6DD4)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF2E6DD4).withValues(alpha: 0.5),
                      blurRadius: 40,
                      spreadRadius: 8,
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Text(
                  _initials.isEmpty ? '?' : _initials,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                patientName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 32),
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: Color(0xFF5A94FF),
                  strokeWidth: 2,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                status,
                style: const TextStyle(
                    color: Colors.white54, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Error screen ─────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onBack});
  final String error;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.center,
          radius: 1.2,
          colors: [Color(0xFF1E3A6E), Color(0xFF0A1628)],
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF3B30).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFFFF3B30).withValues(alpha: 0.3),
                    width: 1.5,
                  ),
                ),
                child: const Icon(
                  Icons.call_end_rounded,
                  color: Color(0xFFFF3B30),
                  size: 30,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Could not join call',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                error,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              GestureDetector(
                onTap: onBack,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 36, vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2E6DD4),
                    borderRadius: BorderRadius.circular(100),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF2E6DD4).withValues(alpha: 0.4),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Text(
                    'Go back',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
