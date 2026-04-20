import 'dart:async';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'dart:convert';

class RoomInfo {
  final String roomCode;
  final String roomName;
  final String host;
  final List<String> participants;
  final int maxParticipants;
  final bool isPublic;

  RoomInfo({
    required this.roomCode,
    required this.roomName,
    required this.host,
    required this.participants,
    required this.maxParticipants,
    required this.isPublic,
  });

  factory RoomInfo.fromJson(Map<String, dynamic> json) {
    return RoomInfo(
      roomCode: json['room_code'] ?? '',
      roomName: json['room_name'] ?? '',
      host: json['host'] ?? '',
      participants: List<String>.from(json['participants'] ?? []),
      maxParticipants: json['max_participants'] ?? 2,
      isPublic: json['is_public'] ?? true,
    );
  }
}

class RoomService {
  late WebSocketChannel _channel;
  final String _serverUrl;
  bool _isConnected = false;
  String? _currentRoomCode;
  String _deviceSerial = '';

  final _roomController = StreamController<RoomInfo>.broadcast();
  final _participantsController = StreamController<List<String>>.broadcast();
  final _errorController = StreamController<String>.broadcast();

  Stream<RoomInfo> get onRoomCreated => _roomController.stream;
  Stream<List<String>> get onParticipantsChanged => _participantsController.stream;
  Stream<String> get onError => _errorController.stream;

  RoomService({
    required String serverUrl,
  }) : _serverUrl = serverUrl;

  Future<bool> connect(String deviceSerial) async {
    try {
      _deviceSerial = deviceSerial;
      _channel = WebSocketChannel.connect(
        Uri.parse(_serverUrl),
      );

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

  void sendMessage(String messageType, Map<String, dynamic> data) {
    if (!_isConnected) {
      print('Error: Not connected to signaling server');
      return;
    }

    final message = {
      'type': messageType,
      'data': {
        'device_serial': _deviceSerial,
        ...data,
      },
      'timestamp': DateTime.now().toIso8601String(),
    };

    _channel.sink.add(jsonEncode(message));
  }

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

  void _handleMessage(Map<String, dynamic> message) {
    final type = message['type'];
    final data = message['data'];

    switch (type) {
      case 'room_created':
        _currentRoomCode = data['room_code'];
        _roomController.add(RoomInfo.fromJson(data));
        break;

      case 'room_joined':
        _currentRoomCode = data['room_code'];
        _roomController.add(RoomInfo.fromJson(data));
        _participantsController.add(List<String>.from(data['participants']));
        break;

      case 'room_left':
        _currentRoomCode = null;
        break;

      case 'participant_joined':
        _participantsController.add(List<String>.from(data['participants']));
        break;

      case 'participant_left':
        _participantsController.add(List<String>.from(data['participants']));
        break;

      case 'host_changed':
        _roomController.add(RoomInfo(
          roomCode: _currentRoomCode ?? '',
          roomName: '',
          host: data['new_host'],
          participants: [],
          maxParticipants: 2,
          isPublic: true,
        ));
        break;

      case 'room_list':
        break;

      case 'error':
        _errorController.add(data['error'] ?? 'Unknown error');
        break;

      case 'offer':
        _onOfferReceived(data);
        break;

      case 'answer':
        _onAnswerReceived(data);
        break;

      case 'ice_candidate':
        _onIceCandidateReceived(data);
        break;
    }
  }

  Function(Map<String, dynamic>)? onOfferReceived;
  Function(Map<String, dynamic>)? onAnswerReceived;
  Function(Map<String, dynamic>)? onIceCandidateReceived;

  void _onOfferReceived(Map<String, dynamic> data) {
    onOfferReceived?.call(data);
  }

  void _onAnswerReceived(Map<String, dynamic> data) {
    onAnswerReceived?.call(data);
  }

  void _onIceCandidateReceived(Map<String, dynamic> data) {
    onIceCandidateReceived?.call(data);
  }

  Future<bool> createRoom({
    String? roomName,
    int maxParticipants = 2,
    bool isPublic = true,
  }) async {
    if (!_isConnected) return false;

    sendMessage('room_create', {
      'room_name': roomName,
      'max_participants': maxParticipants,
      'is_public': isPublic,
    });

    return true;
  }

  Future<bool> joinRoom(String roomCode) async {
    if (!_isConnected) return false;

    sendMessage('room_join', {
      'room_code': roomCode,
    });

    return true;
  }

  Future<void> leaveRoom() async {
    if (!_isConnected || _currentRoomCode == null) return;

    sendMessage('room_leave', {
      'room_code': _currentRoomCode,
    });

    _currentRoomCode = null;
  }

  Future<List<RoomInfo>> getPublicRooms() async {
    if (!_isConnected) return [];

    sendMessage('room_list', {});

    await Future.delayed(const Duration(milliseconds: 500));
    return [];
  }

  void sendOfferToRoom(Map<String, dynamic> sdp) {
    if (_currentRoomCode == null) {
      _errorController.add('Not in a room');
      return;
    }

    sendMessage('offer', {
      'room_code': _currentRoomCode,
      'sdp': sdp,
    });
  }

  void sendAnswerToRoom(Map<String, dynamic> sdp) {
    if (_currentRoomCode == null) {
      _errorController.add('Not in a room');
      return;
    }

    sendMessage('answer', {
      'room_code': _currentRoomCode,
      'sdp': sdp,
    });
  }

  void sendIceCandidateToRoom(Map<String, dynamic> candidate) {
    if (_currentRoomCode == null) {
      _errorController.add('Not in a room');
      return;
    }

    sendMessage('ice_candidate', {
      'room_code': _currentRoomCode,
      'candidate': candidate,
    });
  }

  String? get currentRoomCode => _currentRoomCode;
  bool get isConnected => _isConnected;
  bool get isInRoom => _currentRoomCode != null;

  void disconnect() {
    if (_isConnected) {
      if (_currentRoomCode != null) {
        leaveRoom();
      }
      _channel.sink.close();
      _isConnected = false;
    }
  }

  void dispose() {
    disconnect();
    _roomController.close();
    _participantsController.close();
    _errorController.close();
  }
}