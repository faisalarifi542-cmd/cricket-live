import { getSubscriber, getRedis } from '../lib/redis.js';
import { wsConnectionsGauge, wsMessagesTotal } from '../lib/metrics.js';
import config from '../config/index.js';
import logger from '../lib/logger.js';

/**
 * WebSocket Gateway — manages rooms, subscriptions, and broadcasting.
 *
 * Architecture:
 *   Workers → Redis PubSub → WS Gateway → Client WebSockets
 *
 * Rooms:
 *   match:{id}  — per-match live updates
 *   live        — all live match score summaries
 *
 * Events emitted to clients:
 *   score_update, commentary_update, innings_update,
 *   match_started, match_finished
 */

/** @type {Map<import('ws').WebSocket, Set<string>>} client → subscribed rooms */
const clientRooms = new Map();

/** @type {Map<string, Set<import('ws').WebSocket>>} room → connected clients */
const rooms = new Map();

let heartbeatTimer = null;

/**
 * Register the WS gateway with a Fastify server that has @fastify/websocket.
 */
export function registerWebSocket(fastify) {
  // Main WS endpoint
  fastify.get('/ws', { websocket: true }, (socket, req) => {
    handleConnection(socket, req);
  });

  // Start Redis subscriber for worker events
  startRedisSubscriber();

  // Heartbeat to detect dead connections
  heartbeatTimer = setInterval(() => {
    for (const [client] of clientRooms) {
      if (client.readyState !== 1) { // not OPEN
        removeClient(client);
        continue;
      }
      try {
        client.ping();
      } catch {
        removeClient(client);
      }
    }
  }, config.ws.heartbeatInterval);

  logger.info('WebSocket gateway registered');
}

function handleConnection(socket, req) {
  // Enforce max connections
  if (clientRooms.size >= config.ws.maxConnections) {
    socket.send(JSON.stringify({ event: 'error', data: { message: 'Server at capacity' } }));
    socket.close(1013, 'Server at capacity');
    return;
  }

  clientRooms.set(socket, new Set());
  wsConnectionsGauge.inc();

  logger.debug({ msg: 'WS client connected', total: clientRooms.size });

  // Send welcome
  send(socket, 'connected', { message: 'Connected to Cricket Scoring API', timestamp: Date.now() });

  socket.on('message', (raw) => {
    try {
      const msg = JSON.parse(raw.toString());
      handleMessage(socket, msg);
    } catch {
      send(socket, 'error', { message: 'Invalid JSON' });
    }
  });

  socket.on('close', () => {
    removeClient(socket);
  });

  socket.on('error', (err) => {
    logger.warn({ msg: 'WS client error', error: err.message });
    removeClient(socket);
  });

  socket.on('pong', () => {
    // Client is alive
  });
}

function handleMessage(socket, msg) {
  const { action, room, rooms: roomList } = msg;

  switch (action) {
    case 'subscribe': {
      const targets = roomList || (room ? [room] : []);
      for (const r of targets) {
        joinRoom(socket, r);
      }
      send(socket, 'subscribed', { rooms: targets });
      break;
    }
    case 'unsubscribe': {
      const targets = roomList || (room ? [room] : []);
      for (const r of targets) {
        leaveRoom(socket, r);
      }
      send(socket, 'unsubscribed', { rooms: targets });
      break;
    }
    case 'ping': {
      send(socket, 'pong', { timestamp: Date.now() });
      break;
    }
    default: {
      send(socket, 'error', { message: `Unknown action: ${action}` });
    }
  }
}

// ====================================================
// Room management
// ====================================================

function joinRoom(socket, roomName) {
  if (!roomName) return;

  // Get or create room
  if (!rooms.has(roomName)) {
    rooms.set(roomName, new Set());
  }
  rooms.get(roomName).add(socket);

  // Track client's rooms
  const clientSet = clientRooms.get(socket);
  if (clientSet) clientSet.add(roomName);

  logger.debug({ msg: 'Client joined room', room: roomName, roomSize: rooms.get(roomName).size });
}

function leaveRoom(socket, roomName) {
  const room = rooms.get(roomName);
  if (room) {
    room.delete(socket);
    if (room.size === 0) rooms.delete(roomName);
  }

  const clientSet = clientRooms.get(socket);
  if (clientSet) clientSet.delete(roomName);
}

function removeClient(socket) {
  const clientSet = clientRooms.get(socket);
  if (clientSet) {
    for (const roomName of clientSet) {
      const room = rooms.get(roomName);
      if (room) {
        room.delete(socket);
        if (room.size === 0) rooms.delete(roomName);
      }
    }
  }
  clientRooms.delete(socket);
  wsConnectionsGauge.dec();

  try { socket.close(); } catch { /* ignore */ }
}

// ====================================================
// Broadcasting
// ====================================================

function broadcast(roomName, event, data) {
  const room = rooms.get(roomName);
  if (!room || room.size === 0) return;

  const payload = JSON.stringify({ event, data, timestamp: Date.now() });
  let sent = 0;

  for (const client of room) {
    if (client.readyState === 1) { // OPEN
      try {
        client.send(payload);
        sent++;
      } catch {
        removeClient(client);
      }
    } else {
      removeClient(client);
    }
  }

  wsMessagesTotal.inc({ event }, sent);
  logger.debug({ msg: 'Broadcast', room: roomName, event, clients: sent });
}

function send(socket, event, data) {
  if (socket.readyState !== 1) return;
  try {
    socket.send(JSON.stringify({ event, data, timestamp: Date.now() }));
  } catch { /* ignore */ }
}

// ====================================================
// Redis PubSub — receive events from workers
// ====================================================

function startRedisSubscriber() {
  const subscriber = getSubscriber();

  subscriber.subscribe('ws:events', (err) => {
    if (err) {
      logger.error({ msg: 'Redis subscribe failed', error: err.message });
      return;
    }
    logger.info('WS gateway subscribed to ws:events channel');
  });

  subscriber.on('message', (channel, message) => {
    if (channel !== 'ws:events') return;

    try {
      const { event, matchId, data, changes } = JSON.parse(message);

      // Broadcast to match-specific room
      if (matchId) {
        broadcast(`match:${matchId}`, event, data);
      }

      // Also broadcast score_update and match events to the global "live" room
      if (['score_update', 'match_started', 'match_finished'].includes(event)) {
        broadcast('live', event, { matchId, ...data });
      }
    } catch (err) {
      logger.error({ msg: 'WS event parse failed', error: err.message });
    }
  });
}

/**
 * Get current gateway stats.
 */
export function getGatewayStats() {
  const roomStats = {};
  for (const [name, clients] of rooms) {
    roomStats[name] = clients.size;
  }

  return {
    totalConnections: clientRooms.size,
    totalRooms: rooms.size,
    rooms: roomStats,
  };
}

/**
 * Graceful shutdown.
 */
export function shutdownGateway() {
  if (heartbeatTimer) clearInterval(heartbeatTimer);

  for (const [client] of clientRooms) {
    send(client, 'server_shutdown', { message: 'Server restarting' });
    try { client.close(1001, 'Server shutdown'); } catch { /* ignore */ }
  }

  clientRooms.clear();
  rooms.clear();
  logger.info('WebSocket gateway shut down');
}
