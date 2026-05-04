import express from 'express';
import { WebSocketServer } from 'ws';
import { createServer } from 'http';
import cors from 'cors';
import { v4 as uuidv4 } from 'uuid';
import pino from 'pino';
import dotenv from 'dotenv';
import RateLimiter from './rate_limiter.js';

dotenv.config();

const logger = pino({ level: process.env.LOG_LEVEL || 'info' });
const app = express();
const port = Number(process.env.PORT || 3000);
const allowedOrigins = (process.env.ALLOWED_ORIGINS || '')
  .split(',')
  .map((origin) => origin.trim())
  .filter(Boolean);

const httpLimiter = new RateLimiter({ windowMs: 60000, maxRequests: 100 });
const wsLimiter = new RateLimiter({ windowMs: 60000, maxRequests: 30 });

app.use(cors({
  origin: (origin, callback) => {
    if (!origin) return callback(null, true);
    if (allowedOrigins.length === 0) return callback(new Error('CORS origin not allowed'));
    if (allowedOrigins.includes(origin)) return callback(null, true);
    return callback(new Error('CORS origin not allowed'));
  },
}));
app.use(express.json());
app.use(RateLimiter.middleware(httpLimiter));

const server = createServer(app);
const wss = new WebSocketServer({
  server,
  perMessageDeflate: false,
  clientTracking: true,
  verifyClient: RateLimiter.wsValidator(httpLimiter),
});

const clients = new Map(); // Map<deviceSerial, WebSocket>
const sessionMap = new Map(); // Map<sessionId, { device1, device2 }>
const rooms = new Map(); // Map<roomCode, room>

wss.on('connection', (ws, req) => {
  const connectionId = uuidv4();
  const clientIp = req.socket.remoteAddress || 'unknown';
  let deviceSerial = null;

  const setDeviceSerial = (serial) => {
    if (!serial) return;
    deviceSerial = serial;
  };

  logger.info({ connectionId, clientIp }, 'New websocket connection');

  ws.on('message', async (message) => {
    try {
      const parsedMessage = JSON.parse(message.toString());

      if (!deviceSerial) {
        const serial = parsedMessage?.data?.device_serial || parsedMessage?.data?.deviceSerial;
        if (serial) {
          setDeviceSerial(serial);
        }
      }

      const limiterId = deviceSerial || clientIp;
      if (!wsLimiter.isAllowed(limiterId)) {
        ws.send(JSON.stringify({
          type: 'error',
          data: {
            error: 'Too many messages',
            retryAfter: wsLimiter.getResetTime(limiterId),
          },
        }));
        return;
      }

      await handleSignalingMessage(ws, parsedMessage, setDeviceSerial, deviceSerial);
    } catch (error) {
      logger.error({ err: error }, 'Error handling websocket message');
      ws.send(JSON.stringify({ type: 'error', data: { error: 'Invalid message format' } }));
    }
  });

  ws.on('close', () => {
    if (deviceSerial) {
      clients.delete(deviceSerial);
      logger.info({ deviceSerial }, 'Device disconnected');
    }
  });

  ws.on('error', (error) => {
    logger.error({ err: error, connectionId }, 'WebSocket error');
  });
});

async function handleSignalingMessage(ws, message, setDeviceSerial, boundDeviceSerial) {
  const { type, data = {} } = message;
  if (type !== 'device_registration' && !boundDeviceSerial) {
    ws.send(JSON.stringify({ type: 'error', data: { error: 'Device must register first' } }));
    return;
  }

  if (!_isAuthorizedMessage(type, data, boundDeviceSerial)) {
    ws.send(JSON.stringify({ type: 'error', data: { error: 'Unauthorized message sender' } }));
    return;
  }

  switch (type) {
    case 'device_registration':
      handleDeviceRegistration(ws, data, setDeviceSerial);
      break;
    case 'pairing_request':
      handlePairingRequest(ws, data);
      break;
    case 'room_create':
      handleRoomCreate(ws, data);
      break;
    case 'room_join':
      handleRoomJoin(ws, data);
      break;
    case 'room_leave':
      handleRoomLeave(ws, data);
      break;
    case 'room_list':
      handleRoomList(ws);
      break;
    case 'offer':
      handleOffer(ws, data);
      break;
    case 'answer':
      handleAnswer(ws, data);
      break;
    case 'ice_candidate':
      handleIceCandidate(ws, data);
      break;
    case 'connection_state':
      handleConnectionState(data);
      break;
    default:
      logger.warn({ type }, 'Unknown message type');
  }
}

function handleDeviceRegistration(ws, data, setDeviceSerial) {
  const deviceSerial = data.device_serial || data.deviceSerial;

  if (!deviceSerial) {
    ws.send(JSON.stringify({ type: 'error', data: { error: 'Missing device_serial' } }));
    return;
  }

  clients.set(deviceSerial, ws);
  setDeviceSerial(deviceSerial);

  ws.send(JSON.stringify({
    type: 'registration_success',
    data: { device_serial: deviceSerial, server_timestamp: new Date().toISOString() },
  }));
}

function handlePairingRequest(ws, data) {
  const { target_device: targetDevice } = data;

  if (!targetDevice) {
    ws.send(JSON.stringify({ type: 'error', data: { error: 'Missing target_device' } }));
    return;
  }

  const targetWs = clients.get(targetDevice);
  if (!targetWs) {
    ws.send(JSON.stringify({ type: 'pairing_failed', data: { error: 'Target device not found' } }));
    return;
  }

  const pairingCode = Math.floor(Math.random() * 1000000).toString().padStart(6, '0');
  targetWs.send(JSON.stringify({
    type: 'pairing_request_received',
    data: {
      initiator_device: data.device_serial,
      pairing_code: pairingCode,
      timestamp: new Date().toISOString(),
    },
  }));
}

function handleRoomCreate(ws, data) {
  const { device_serial: deviceSerial, room_name: roomName, max_participants: maxParticipants, is_public: isPublic } = data;

  if (!deviceSerial) {
    ws.send(JSON.stringify({ type: 'error', data: { error: 'Missing device_serial' } }));
    return;
  }

  const roomCode = Math.floor(Math.random() * 1000000).toString().padStart(6, '0');
  const room = {
    host: deviceSerial,
    name: roomName || `Room ${roomCode}`,
    participants: [deviceSerial],
    maxParticipants: maxParticipants || 2,
    isPublic: isPublic !== false,
    status: 'waiting',
    createdAt: new Date().toISOString(),
  };

  rooms.set(roomCode, room);

  ws.send(JSON.stringify({
    type: 'room_created',
    data: {
      room_code: roomCode,
      room_name: room.name,
      max_participants: room.maxParticipants,
      is_public: room.isPublic,
      participants: room.participants,
    },
  }));
}

function handleRoomJoin(ws, data) {
  const { room_code: roomCode, device_serial: deviceSerial } = data;

  if (!roomCode || !deviceSerial) {
    ws.send(JSON.stringify({ type: 'error', data: { error: 'Missing room_code or device_serial' } }));
    return;
  }

  const room = rooms.get(roomCode);
  if (!room) {
    ws.send(JSON.stringify({ type: 'error', data: { error: 'Room not found' } }));
    return;
  }

  if (room.participants.length >= room.maxParticipants) {
    ws.send(JSON.stringify({ type: 'error', data: { error: 'Room is full' } }));
    return;
  }

  if (room.participants.includes(deviceSerial)) {
    ws.send(JSON.stringify({ type: 'error', data: { error: 'Already in room' } }));
    return;
  }

  room.participants.push(deviceSerial);

  ws.send(JSON.stringify({
    type: 'room_joined',
    data: { room_code: roomCode, room_name: room.name, host: room.host, participants: room.participants },
  }));

  room.participants.forEach((participant) => {
    if (participant === deviceSerial) return;
    const participantWs = clients.get(participant);
    if (!participantWs) return;

    participantWs.send(JSON.stringify({
      type: 'participant_joined',
      data: { device_serial: deviceSerial, participants: room.participants },
    }));
  });
}

function handleRoomLeave(ws, data) {
  const { room_code: roomCode, device_serial: deviceSerial } = data;

  if (!roomCode || !deviceSerial) {
    ws.send(JSON.stringify({ type: 'error', data: { error: 'Missing room_code or device_serial' } }));
    return;
  }

  const room = rooms.get(roomCode);
  if (!room) {
    ws.send(JSON.stringify({ type: 'error', data: { error: 'Room not found' } }));
    return;
  }

  room.participants = room.participants.filter((p) => p !== deviceSerial);

  if (room.participants.length === 0) {
    rooms.delete(roomCode);
    ws.send(JSON.stringify({ type: 'room_left', data: { room_code: roomCode } }));
    return;
  }

  if (room.host === deviceSerial) {
    room.host = room.participants[0];
  }

  room.participants.forEach((participant) => {
    const participantWs = clients.get(participant);
    if (!participantWs) return;

    participantWs.send(JSON.stringify({
      type: 'participant_left',
      data: { device_serial: deviceSerial, participants: room.participants, host: room.host },
    }));
  });

  ws.send(JSON.stringify({ type: 'room_left', data: { room_code: roomCode } }));
}

function handleRoomList(ws) {
  const publicRooms = [];

  rooms.forEach((room, code) => {
    if (room.isPublic && room.status === 'waiting') {
      publicRooms.push({
        room_code: code,
        room_name: room.name,
        host: room.host,
        participants: room.participants.length,
        max_participants: room.maxParticipants,
      });
    }
  });

  ws.send(JSON.stringify({ type: 'room_list', data: { rooms: publicRooms } }));
}

function relayToRoom(ws, roomCode, payloadType, payloadData) {
  const room = rooms.get(roomCode);
  if (!room) {
    ws.send(JSON.stringify({ type: 'error', data: { error: 'Room not found' } }));
    return;
  }

  room.participants.forEach((participant) => {
    const participantWs = clients.get(participant);
    if (participantWs && participantWs !== ws) {
      participantWs.send(JSON.stringify({ type: payloadType, data: payloadData }));
    }
  });
}

function relayToDevice(ws, targetDevice, payloadType, payloadData) {
  const targetWs = clients.get(targetDevice);
  if (!targetWs) {
    ws.send(JSON.stringify({ type: 'error', data: { error: 'Target device not available' } }));
    return;
  }

  targetWs.send(JSON.stringify({ type: payloadType, data: payloadData }));
}

function handleOffer(ws, data) {
  const { target_device: targetDevice, room_code: roomCode, sdp, device_serial: deviceSerial } = data;

  if (roomCode) {
    relayToRoom(ws, roomCode, 'offer', { sdp, from: deviceSerial });
  } else if (targetDevice) {
    relayToDevice(ws, targetDevice, 'offer', { sdp, from: deviceSerial });
  }
}

function handleAnswer(ws, data) {
  const { target_device: targetDevice, room_code: roomCode, sdp, device_serial: deviceSerial } = data;

  if (roomCode) {
    relayToRoom(ws, roomCode, 'answer', { sdp, from: deviceSerial });
  } else if (targetDevice) {
    relayToDevice(ws, targetDevice, 'answer', { sdp, from: deviceSerial });
  }
}

function handleIceCandidate(ws, data) {
  const { target_device: targetDevice, room_code: roomCode, candidate, device_serial: deviceSerial } = data;

  if (roomCode) {
    relayToRoom(ws, roomCode, 'ice_candidate', { candidate, from: deviceSerial });
  } else if (targetDevice) {
    relayToDevice(ws, targetDevice, 'ice_candidate', { candidate, from: deviceSerial });
  }
}

function handleConnectionState(data) {
  logger.info({ state: data.state, target: data.target_device }, 'Connection state update');
}

function _isAuthorizedMessage(type, data, boundDeviceSerial) {
  if (type === 'device_registration') return true;
  if (!boundDeviceSerial) return false;

  const senderSerial = data?.device_serial || data?.deviceSerial;
  const senderRequiredTypes = new Set([
    'pairing_request',
    'room_create',
    'room_join',
    'room_leave',
    'offer',
    'answer',
    'ice_candidate',
    'connection_state',
  ]);

  if (senderRequiredTypes.has(type) && senderSerial !== boundDeviceSerial) {
    return false;
  }

  if ((type === 'offer' || type === 'answer' || type === 'ice_candidate') && data?.room_code) {
    const room = rooms.get(data.room_code);
    if (!room || !room.participants.includes(boundDeviceSerial)) {
      return false;
    }
  }

  return true;
}

app.get('/health', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString(), clients: clients.size });
});

app.get('/stats', (req, res) => {
  res.json({
    connected_clients: clients.size,
    active_sessions: sessionMap.size,
    active_rooms: rooms.size,
    uptime: process.uptime(),
    timestamp: new Date().toISOString(),
  });
});

app.get('/config', (req, res) => {
  res.json({ websocket_url: process.env.PUBLIC_WS_URL || `ws://localhost:${port}` });
});

server.listen(port, () => {
  logger.info({ port }, 'Signaling server listening');
});

process.on('SIGTERM', () => {
  logger.info('SIGTERM received, shutting down gracefully...');
  server.close(() => {
    logger.info('Server closed');
    process.exit(0);
  });
});
