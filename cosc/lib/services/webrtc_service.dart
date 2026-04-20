import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'dart:convert';
import 'signaling_service.dart';
import 'room_service.dart';

class WebRTCService {
  late RTCPeerConnection _peerConnection;
  SignalingService? _signalingService;
  RoomService? _roomService;
  
  RTCVideoRenderer? localRenderer;
  RTCVideoRenderer? remoteRenderer;
  
  String? _targetDevice;
  String? _roomCode;
  
  static const List<String> stunServers = [
    'stun:stun.l.google.com:19302',
    'stun:stun1.l.google.com:19302',
    'stun:stun2.l.google.com:19302',
    'stun:stun3.l.google.com:19302',
    'stun:stun4.l.google.com:19302',
  ];

  // Connection state callbacks
  Function(RTCPeerConnectionState)? onConnectionStateChange;
  Function(RTCIceConnectionState)? onIceConnectionStateChange;
  Function(RTCSignalingState)? onSignalingStateChange;
  Function(RTCIceGatheringState)? onIceGatheringStateChange;
  Function(MediaStream)? onRemoteStreamReceived;
  Function()? onConnectionLost;
  Function(Map<String, dynamic>)? onRoomOfferReceived;
  Function(Map<String, dynamic>)? onRoomAnswerReceived;
  Function(Map<String, dynamic>)? onRoomIceCandidateReceived;

  WebRTCService({
    SignalingService? signalingService,
    RoomService? roomService,
    String? targetDevice,
    String? roomCode,
  }) : _signalingService = signalingService,
       _roomService = roomService,
       _targetDevice = targetDevice,
       _roomCode = roomCode;

  Future<bool> initialize({bool useAudio = true, bool useVideo = true}) async {
    if (_roomService != null) {
      _roomService!.onOfferReceived = (data) => onRoomOfferReceived?.call(data);
      _roomService!.onAnswerReceived = (data) => onRoomAnswerReceived?.call(data);
      _roomService!.onIceCandidateReceived = (data) => onRoomIceCandidateReceived?.call(data);
    }
    return true;
  }

  /// Initialize WebRTC peer connection
  Future<bool> initialize({
    bool useAudio = true,
    bool useVideo = true,
    List<String> turnServers = const [],
  }) async {
    try {
      // Request media permissions
      if (useAudio || useVideo) {
        final Map<String, dynamic> mediaConstraints = {
          'audio': useAudio ? {'echoCancellation': true} : false,
          'video': useVideo
              ? {
                  'width': {'ideal': 1280},
                  'height': {'ideal': 720},
                  'frameRate': {'ideal': 30},
                }
              : false,
        };

        // Get user media
        final stream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
        
        // Initialize renderers
        localRenderer = RTCVideoRenderer();
        await localRenderer!.initialize();
        localRenderer!.srcObject = stream;
      }

      // Create peer connection
      final configuration = {
        'iceServers': [
          ..._buildIceServers(stunServers),
          if (turnServers.isNotEmpty) ..._buildTurnServers(turnServers),
        ],
      };

      _peerConnection = await createPeerConnection(configuration);
      _setupPeerConnectionHandlers();

      // Add local stream tracks to peer connection
      if (useAudio || useVideo) {
        final stream = localRenderer!.srcObject as MediaStream;
        for (final track in stream.getTracks()) {
          await _peerConnection.addTrack(track, stream);
        }
      }

      return true;
    } catch (e) {
      print('Error initializing WebRTC: $e');
      return false;
    }
  }

  /// Build ICE server configurations from STUN URLs
  List<Map<String, dynamic>> _buildIceServers(List<String> stunUrls) {
    return [
      {
        'urls': stunUrls,
      }
    ];
  }

  /// Build TURN server configurations
  List<Map<String, dynamic>> _buildTurnServers(List<String> turnUrls) {
    return turnUrls.map((url) {
      final parts = url.split('@');
      if (parts.length == 2) {
        final credentials = parts[0].split(':');
        return {
          'urls': [parts[1]],
          'username': credentials[0],
          'credential': credentials[1],
        };
      }
      return {'urls': [url]};
    }).toList();
  }

  /// Setup peer connection event handlers
  void _setupPeerConnectionHandlers() {
    _peerConnection.onConnectionState = (RTCPeerConnectionState state) {
      print('Peer connection state: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        onConnectionLost?.call();
      }
      onConnectionStateChange?.call(state);
    };

    _peerConnection.onIceConnectionState =
        (RTCIceConnectionState state) {
      print('ICE connection state: $state');
      onIceConnectionStateChange?.call(state);
    };

    _peerConnection.onSignalingState = (RTCSignalingState state) {
      print('Signaling state: $state');
      onSignalingStateChange?.call(state);
    };

    _peerConnection.onIceGatheringState = (RTCIceGatheringState state) {
      print('ICE gathering state: $state');
      onIceGatheringStateChange?.call(state);
    };

    _peerConnection.onAddStream = (MediaStream stream) {
      print('Remote stream received');
      remoteRenderer?.srcObject = stream;
      onRemoteStreamReceived?.call(stream);
    };

    _peerConnection.onTrack = (RTCTrackEvent event) {
      print('Remote track received: ${event.track.kind}');
      if (remoteRenderer != null) {
        remoteRenderer!.srcObject = event.streams[0];
      }
    };

    _peerConnection.onIceCandidate = (RTCIceCandidate candidate) {
      print('New ICE candidate: ${candidate.candidate}');
      // Send ICE candidate through signaling server
      _signalingService.sendIceCandidate(
        'target_device', // Will be updated with actual target
        {
          'candidate': candidate.candidate,
          'sdpMLineIndex': candidate.sdpMLineIndex,
          'sdpMid': candidate.sdpMid,
        },
      );
    };
  }

  /// Create WebRTC offer
  Future<bool> createOffer(String targetDevice) async {
    try {
      final offer = await _peerConnection.createOffer({});
      await _peerConnection.setLocalDescription(offer);

      _signalingService.sendOffer(
        targetDevice,
        {
          'sdp': offer.sdp,
          'type': offer.type,
        },
      );

      return true;
    } catch (e) {
      print('Error creating offer: $e');
      return false;
    }
  }

  /// Create WebRTC answer
  Future<bool> createAnswer(String targetDevice) async {
    try {
      final answer = await _peerConnection.createAnswer({});
      await _peerConnection.setLocalDescription(answer);

      _signalingService.sendAnswer(
        targetDevice,
        {
          'sdp': answer.sdp,
          'type': answer.type,
        },
      );

      return true;
    } catch (e) {
      print('Error creating answer: $e');
      return false;
    }
  }

  /// Handle remote offer
  Future<bool> handleOffer(String offerSdp) async {
    try {
      final offer = RTCSessionDescription(offerSdp, 'offer');
      await _peerConnection.setRemoteDescription(offer);
      return true;
    } catch (e) {
      print('Error handling offer: $e');
      return false;
    }
  }

  /// Handle remote answer
  Future<bool> handleAnswer(String answerSdp) async {
    try {
      final answer = RTCSessionDescription(answerSdp, 'answer');
      await _peerConnection.setRemoteDescription(answer);
      return true;
    } catch (e) {
      print('Error handling answer: $e');
      return false;
    }
  }

  /// Add ICE candidate
  Future<bool> addIceCandidate(
    String candidate,
    int? sdpMLineIndex,
    String? sdpMid,
  ) async {
    try {
      final iceCandidate = RTCIceCandidate(
        candidate,
        sdpMid,
        sdpMLineIndex,
      );
      await _peerConnection.addCandidate(iceCandidate);
      return true;
    } catch (e) {
      print('Error adding ICE candidate: $e');
      return false;
    }
  }

  /// Get local video stream
  MediaStream? getLocalStream() {
    return localRenderer?.srcObject as MediaStream?;
  }

  /// Get remote video stream
  MediaStream? getRemoteStream() {
    return remoteRenderer?.srcObject as MediaStream?;
  }

  /// Toggle audio
  Future<void> toggleAudio(bool enable) async {
    final stream = getLocalStream();
    if (stream != null) {
      for (final track in stream.getAudioTracks()) {
        await track.enabled(enable);
      }
    }
  }

  /// Toggle video
  Future<void> toggleVideo(bool enable) async {
    final stream = getLocalStream();
    if (stream != null) {
      for (final track in stream.getVideoTracks()) {
        await track.enabled(enable);
      }
    }
  }

  /// Switch camera
  Future<void> switchCamera() async {
    final stream = getLocalStream();
    if (stream != null) {
      for (final track in stream.getVideoTracks()) {
        await track.switchCamera();
      }
    }
  }

  /// Get connection state
  RTCPeerConnectionState? getConnectionState() {
    return _peerConnection.connectionState;
  }

  /// Get ICE connection state
  RTCIceConnectionState? getIceConnectionState() {
    return _peerConnection.iceConnectionState;
  }

  /// Dispose and cleanup resources
  Future<void> dispose() async {
    try {
      final stream = getLocalStream();
      if (stream != null) {
        for (final track in stream.getTracks()) {
          await track.stop();
        }
      }

      await _peerConnection.close();
      await localRenderer?.dispose();
      await remoteRenderer?.dispose();
    } catch (e) {
      print('Error disposing WebRTC: $e');
    }
  }
}
