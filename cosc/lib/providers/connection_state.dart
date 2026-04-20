import 'package:flutter/material.dart';
import '../services/webrtc_service.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class ConnectionState extends ChangeNotifier {
  WebRTCService? _webRtcService;
  RTCPeerConnectionState? _peerConnectionState;
  RTCIceConnectionState? _iceConnectionState;
  bool _isAudioEnabled = true;
  bool _isVideoEnabled = true;
  bool _isConnected = false;
  String? _errorMessage;
  String? _roomCode;

  WebRTCService? get webRtcService => _webRtcService;
  RTCPeerConnectionState? get peerConnectionState => _peerConnectionState;
  RTCIceConnectionState? get iceConnectionState => _iceConnectionState;
  bool get isAudioEnabled => _isAudioEnabled;
  bool get isVideoEnabled => _isVideoEnabled;
  bool get isConnected => _isConnected;
  String? get errorMessage => _errorMessage;
  String? get roomCode => _roomCode;

  Future<void> initialize({
    required String signalingUrl,
    required String deviceSerial,
    String? targetDevice,
    String? roomCode,
  }) async {
    _roomCode = roomCode;
    
    _webRtcService = WebRTCService(
      signalingUrl: signalingUrl,
      deviceSerial: deviceSerial,
      targetDevice: targetDevice,
      roomCode: roomCode,
    );
    
    await _webRtcService!.initialize();
    
    // Setup callbacks
    _webRtcService!.onConnectionStateChange = (state) {
      _peerConnectionState = state;
      _isConnected = state == RTCPeerConnectionState.RTCPeerConnectionStateConnected;
      _errorMessage = null;
      notifyListeners();
    };

    _webRtcService!.onIceConnectionStateChange = (state) {
      _iceConnectionState = state;
      
      if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        _errorMessage = 'Connection failed. Retrying...';
        _isConnected = false;
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        _isConnected = true;
        _errorMessage = null;
      }
      
      notifyListeners();
    };

    _webRtcService!.onConnectionLost = () {
      _isConnected = false;
      _errorMessage = 'Connection lost';
      notifyListeners();
    };

    notifyListeners();
  }

  Future<void> toggleAudio(bool enable) async {
    _isAudioEnabled = enable;
    await _webRtcService?.toggleAudio(enable);
    notifyListeners();
  }

  Future<void> toggleVideo(bool enable) async {
    _isVideoEnabled = enable;
    await _webRtcService?.toggleVideo(enable);
    notifyListeners();
  }

  Future<void> switchCamera() async {
    await _webRtcService?.switchCamera();
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _webRtcService?.dispose();
    super.dispose();
  }
}
