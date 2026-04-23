let socket;

const el = {
  wsUrl: document.getElementById('wsUrl'),
  deviceSerial: document.getElementById('deviceSerial'),
  roomName: document.getElementById('roomName'),
  maxParticipants: document.getElementById('maxParticipants'),
  roomCode: document.getElementById('roomCode'),
  connectBtn: document.getElementById('connectBtn'),
  disconnectBtn: document.getElementById('disconnectBtn'),
  createRoomBtn: document.getElementById('createRoomBtn'),
  listRoomsBtn: document.getElementById('listRoomsBtn'),
  joinRoomBtn: document.getElementById('joinRoomBtn'),
  leaveRoomBtn: document.getElementById('leaveRoomBtn'),
  status: document.getElementById('status'),
  log: document.getElementById('log'),
};

function log(message, data) {
  const line = `[${new Date().toISOString()}] ${message}`;
  el.log.textContent = `${line}${data ? `\n${JSON.stringify(data, null, 2)}` : ''}\n\n${el.log.textContent}`;
}

function setStatus(status) {
  el.status.textContent = `Status: ${status}`;
}

function send(type, data = {}) {
  if (!socket || socket.readyState !== WebSocket.OPEN) {
    log('Socket ist nicht verbunden');
    return;
  }

  const payload = { type, data, timestamp: new Date().toISOString() };
  socket.send(JSON.stringify(payload));
  log(`Gesendet: ${type}`, payload);
}

el.connectBtn.addEventListener('click', () => {
  const url = el.wsUrl.value.trim();
  const deviceSerial = el.deviceSerial.value.trim();

  if (!url || !deviceSerial) {
    log('Bitte WebSocket URL und Device Serial eingeben.');
    return;
  }

  socket = new WebSocket(url);
  setStatus('verbinde...');

  socket.addEventListener('open', () => {
    setStatus('verbunden');
    send('device_registration', { device_serial: deviceSerial });
  });

  socket.addEventListener('message', (event) => {
    try {
      const data = JSON.parse(event.data);
      log(`Empfangen: ${data.type}`, data.data || data);
    } catch {
      log('Empfangen (raw)', { value: event.data });
    }
  });

  socket.addEventListener('close', () => setStatus('getrennt'));
  socket.addEventListener('error', (event) => log('Socket Fehler', event));
});

el.disconnectBtn.addEventListener('click', () => {
  if (socket) {
    socket.close();
    setStatus('getrennt');
  }
});

el.createRoomBtn.addEventListener('click', () => {
  send('room_create', {
    device_serial: el.deviceSerial.value.trim(),
    room_name: el.roomName.value.trim(),
    max_participants: Number(el.maxParticipants.value || 2),
    is_public: true,
  });
});

el.listRoomsBtn.addEventListener('click', () => send('room_list', {}));

el.joinRoomBtn.addEventListener('click', () => {
  send('room_join', {
    room_code: el.roomCode.value.trim(),
    device_serial: el.deviceSerial.value.trim(),
  });
});

el.leaveRoomBtn.addEventListener('click', () => {
  send('room_leave', {
    room_code: el.roomCode.value.trim(),
    device_serial: el.deviceSerial.value.trim(),
  });
});
