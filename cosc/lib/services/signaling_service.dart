import 'package:web_socket_channel/web_socket_channel.dart';
import 'dart:convert';

class SignalingService {
  late WebSocketChannel _channel;
  final String _serverUrl;
  bool _isConnected = false;
  
  SignalingService({
    required String serverUrl,
  }) : _serverUrl = serverUrl;
  
  /// Connect to the signaling server
  Future<bool> connect(String deviceSerial) async {
    try {
      _channel = WebSocketChannel.connect(
        Uri.parse(_serverUrl),
      );
      
      // Send device registration message
      sendMessage('device_registration', {
        'device_serial': deviceSerial,
        'timestamp': DateTime.now().toIso8601String(),
      });
      
      _isConnected = true;
      _listenToMessages();
      return true;
    } catch (e) {
      print('Error connecting to signaling server: $e');
      return false;
    }
  }
  
  /// Send a message through the signaling channel
  void sendMessage(String messageType, Map<String, dynamic> data) {
    if (!_isConnected) {
      print('Error: Not connected to signaling server');
      return;
    }
    
    final message = {
      'type': messageType,
      'data': data,
      'timestamp': DateTime.now().toIso8601String(),
    };
    
    _channel.sink.add(jsonEncode(message));
  }
  
  /// Listen to incoming messages
  void _listenToMessages() {
    _channel.stream.listen(
      (message) {
        try {
          final decoded = jsonDecode(message);
          _handleMessage(decoded);
        } catch (e) {
          print('Error parsing message: $e');
        }
      },
      onError: (error) {
        print('WebSocket error: $error');
        _isConnected = false;
      },
      onDone: () {
        print('WebSocket connection closed');
        _isConnected = false;
      },
    );
  }
  
  /// Handle incoming signaling messages
  void _handleMessage(Map<String, dynamic> message) {
    final type = message['type'];
    final data = message['data'];
    
    switch (type) {
      case 'offer':
        _onOfferReceived(data);
        break;
      case 'answer':
        _onAnswerReceived(data);
        break;
      case 'ice_candidate':
        _onIceCandidateReceived(data);
        break;
      case 'connection_state':
        _onConnectionStateChange(data);
        break;
      case 'room_created':
      case 'room_joined':
      case 'room_left':
      case 'participant_joined':
      case 'participant_left':
      case 'host_changed':
      case 'room_list':
        print('Room message: $type');
        break;
      default:
        print('Unknown message type: $type');
    }
  }
  
  void _onOfferReceived(Map<String, dynamic> data) {
    // Handle WebRTC offer - will be implemented with flutter_webrtc
    print('Offer received: $data');
  }
  
  void _onAnswerReceived(Map<String, dynamic> data) {
    // Handle WebRTC answer
    print('Answer received: $data');
  }
  
  void _onIceCandidateReceived(Map<String, dynamic> data) {
    // Handle ICE candidate
    print('ICE candidate received: $data');
  }
  
  void _onConnectionStateChange(Map<String, dynamic> data) {
    // Handle connection state updates
    print('Connection state: ${data['state']}');
  }
  
  /// Send pairing request
  void sendPairingRequest(String targetDeviceSerial, String password) {
    sendMessage('pairing_request', {
      'target_device': targetDeviceSerial,
      'password_hash': password, // Should be hashed on client
    });
  }
  
  /// Send WebRTC offer
  void sendOffer(String targetDevice, Map<String, dynamic> sdp) {
    sendMessage('offer', {
      'target_device': targetDevice,
      'sdp': sdp,
    });
  }
  
  /// Send WebRTC answer
  void sendAnswer(String targetDevice, Map<String, dynamic> sdp) {
    sendMessage('answer', {
      'target_device': targetDevice,
      'sdp': sdp,
    });
  }
  
  /// Send ICE candidate
  void sendIceCandidate(String targetDevice, Map<String, dynamic> candidate) {
    sendMessage('ice_candidate', {
      'target_device': targetDevice,
      'candidate': candidate,
    });
  }
  
  /// Check if connected
  bool get isConnected => _isConnected;
  
  /// Disconnect from server
  void disconnect() {
    if (_isConnected) {
      _channel.sink.close();
      _isConnected = false;
    }
  }
}
