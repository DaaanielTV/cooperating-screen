import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/room_service.dart';
import '../services/supabase_service.dart';
import '../services/webrtc_service.dart';
import '../providers/connection_state.dart';

class RoomScreen extends StatefulWidget {
  const RoomScreen({Key? key}) : super(key: key);

  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> {
  late RoomService _roomService;
  String? _currentRoomCode;
  List<String> _participants = [];
  bool _isLoading = false;
  String? _errorMessage;
  RoomInfo? _currentRoom;

  @override
  void initState() {
    super.initState();
    _initRoomService();
  }

  Future<void> _initRoomService() async {
    final supabaseService = context.read<SupabaseService>();
    final deviceSerial = supabaseService.getDeviceSerial() ?? '';
    
    _roomService = RoomService(
      serverUrl: 'ws://localhost:3000',
    );

    final connected = await _roomService.connect(deviceSerial);
    if (!connected) {
      setState(() => _errorMessage = 'Failed to connect to server');
      return;
    }

    _roomService.onRoomCreated.listen((room) {
      if (mounted) {
        setState(() {
          _currentRoom = room;
          _currentRoomCode = room.roomCode;
        });
      }
    });

    _roomService.onParticipantsChanged.listen((participants) {
      if (mounted) {
        setState(() => _participants = participants);
      }
    });

    _roomService.onError.listen((error) {
      if (mounted) {
        setState(() => _errorMessage = error);
      }
    });
  }

  Future<void> _createRoom() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    await _roomService.createRoom(
      roomName: 'My Room',
      maxParticipants: 2,
      isPublic: true,
    );

    await Future.delayed(const Duration(seconds: 1));
    
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _joinRoom(String code) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final success = await _roomService.joinRoom(code);
    
    if (!success && mounted) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to join room';
      });
    }
  }

  Future<void> _leaveRoom() async {
    await _roomService.leaveRoom();
    setState(() {
      _currentRoomCode = null;
      _participants = [];
      _currentRoom = null;
    });
  }

  void _showJoinRoomDialog() {
    final codeController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Join Room'),
        content: TextField(
          controller: codeController,
          decoration: const InputDecoration(
            labelText: 'Room Code',
            hintText: '000000',
          ),
          keyboardType: TextInputType.number,
          maxLength: 6,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              if (codeController.text.length == 6) {
                _joinRoom(codeController.text);
              }
            },
            child: const Text('Join'),
          ),
        ],
      ),
    );
  }

  void _startCall() {
    if (_currentRoomCode == null || _participants.isEmpty) return;
    
    final supabaseService = context.read<SupabaseService>();
    final deviceSerial = supabaseService.getDeviceSerial() ?? '';
    
    context.read<ConnectionState>().initialize(
      signalingUrl: 'ws://localhost:3000',
      deviceSerial: deviceSerial,
      roomCode: _currentRoomCode,
    );

    Navigator.of(context).pushNamed('/webrtc-call');
  }

  @override
  void dispose() {
    _roomService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Room'),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  if (_errorMessage != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.red.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(color: Colors.red.shade900),
                      ),
                    ),
                  
                  if (_currentRoomCode == null) ...[
                    const Spacer(),
                    const Icon(
                      Icons.meeting_room,
                      size: 80,
                      color: Colors.blue,
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Create or Join a Room',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Share your room code with others to start a session',
                      style: TextStyle(color: Colors.grey.shade600),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: _createRoom,
                        icon: const Icon(Icons.add),
                        label: const Text('Create Room'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: _showJoinRoomDialog,
                        icon: const Icon(Icons.login),
                        label: const Text('Join Room'),
                      ),
                    ),
                    const Spacer(),
                  ] else ...[
                    const SizedBox(height: 24),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            const Text(
                              'Room Code',
                              style: TextStyle(fontSize: 14),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _currentRoomCode!,
                              style: const TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 8,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.person, size: 16),
                                const SizedBox(width: 8),
                                Text(
                                  '${_participants.length} participant(s)',
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Participants',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _participants.length,
                        itemBuilder: (context, index) {
                          final participant = _participants[index];
                          return ListTile(
                            leading: CircleAvatar(
                              child: Text('${index + 1}'),
                            ),
                            title: Text(participant),
                            subtitle: index == 0 
                                ? const Text('Host') 
                                : const Text('Participant'),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _participants.isNotEmpty ? _startCall : null,
                            icon: const Icon(Icons.videocam),
                            label: const Text('Start Call'),
                          ),
                        ),
                        const SizedBox(width: 16),
                        OutlinedButton.icon(
                          onPressed: _leaveRoom,
                          icon: const Icon(Icons.exit_to_app),
                          label: const Text('Leave'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}