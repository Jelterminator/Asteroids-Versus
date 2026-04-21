const express = require('express');
const http = require('http');
const WebSocket = require('ws');
const path = require('path');
const compression = require('compression');
const crypto = require('crypto');

/**
 * Asteroids Versus - Unified Signaling & Static Server
 * Implements Cross-Origin Isolation (COOP/COEP) for Godot 4 SharedArrayBuffer support.
 */

const app = express();
const port = process.env.PORT || 8081;

// --- SECURITY HEADERS (COOP/COEP) ---
// These are mandatory for SharedArrayBuffer to work in Godot 4 web exports.
app.use((req, res, next) => {
    res.setHeader('Cross-Origin-Opener-Policy', 'same-origin; report-to="default"');
    res.setHeader('Cross-Origin-Embedder-Policy', 'require-corp; report-to="default"');
    res.setHeader('Cross-Origin-Resource-Policy', 'same-origin');
    res.setHeader('Reporting-Endpoints', 'default="/report-violation"');
    next();
});

// --- REPORTING API ---
// Endpoint to receive security violation reports as recommended by web.dev
app.use(express.json({ type: ['application/json', 'application/reports+json'] }));
app.post('/report-violation', (req, res) => {
    console.warn('⚠️ SECURITY VIOLATION REPORT:', JSON.stringify(req.body, null, 2));
    res.sendStatus(204);
});

// --- OPTIMIZATIONS ---
app.use(compression());

// --- STATIC ASSETS ---
const sitePath = path.join(__dirname, '../site');
app.use(express.static(sitePath));

// Fallback to index.html
app.get('/', (req, res) => {
    res.sendFile(path.join(sitePath, 'index.html'));
});

// --- SIGNALING LOGIC (WebSockets) ---
const server = http.createServer(app);
const wss = new WebSocket.Server({ server });

const MAX_PEERS = 4096;
const MAX_LOBBIES = 1024;
const ALFNUM = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';

const NO_LOBBY_TIMEOUT = 1000;
const SEAL_CLOSE_TIMEOUT = 10000;
const PING_INTERVAL = 10000;

const STR_NO_LOBBY = 'Have not joined lobby yet';
const STR_HOST_DISCONNECTED = 'Room host has disconnected';
const STR_ONLY_HOST_CAN_SEAL = 'Only host can seal the lobby';
const STR_SEAL_COMPLETE = 'Seal complete';
const STR_TOO_MANY_LOBBIES = 'Too many lobbies open, disconnecting';
const STR_ALREADY_IN_LOBBY = 'Already in a lobby';
const STR_LOBBY_DOES_NOT_EXISTS = 'Lobby does not exists';
const STR_LOBBY_IS_SEALED = 'Lobby is sealed';
const STR_INVALID_FORMAT = 'Invalid message format';
const STR_NEED_LOBBY = 'Invalid message when not in a lobby';
const STR_SERVER_ERROR = 'Server error, lobby not found';
const STR_INVALID_DEST = 'Invalid destination';
const STR_INVALID_CMD = 'Invalid command';
const STR_TOO_MANY_PEERS = 'Too many peers connected';
const STR_INVALID_TRANSFER_MODE = 'Invalid transfer mode, must be text';

const CMD = {
	JOIN: 0,
	ID: 1,
	PEER_CONNECT: 2,
	PEER_DISCONNECT: 3,
	OFFER: 4,
	ANSWER: 5,
	CANDIDATE: 6,
	SEAL: 7,
};

function randomInt(low, high) {
	return Math.floor(Math.random() * (high - low + 1) + low);
}

function randomId() {
	return Math.abs(new Int32Array(crypto.randomBytes(4).buffer)[0]);
}

function randomSecret() {
	let out = '';
	for (let i = 0; i < 16; i++) {
		out += ALFNUM[randomInt(0, ALFNUM.length - 1)];
	}
	return out;
}

function ProtoMessage(type, id, data) {
	return JSON.stringify({
		'type': type,
		'id': id,
		'data': data || '',
	});
}

class ProtoError extends Error {
	constructor(code, message) {
		super(message);
		this.code = code;
	}
}

class Peer {
	constructor(id, ws) {
		this.id = id;
		this.ws = ws;
		this.lobby = '';
		// Close connection after 1 sec if client has not joined a lobby
		this.timeout = setTimeout(() => {
			if (!this.lobby) {
				ws.close(4000, STR_NO_LOBBY);
			}
		}, NO_LOBBY_TIMEOUT);
	}
}

class Lobby {
	constructor(name, host, mesh) {
		this.name = name;
		this.host = host;
		this.mesh = mesh;
		this.peers = [];
		this.sealed = false;
		this.closeTimer = -1;
	}

	getPeerId(peer) {
		if (this.host === peer.id) {
			return 1;
		}
		return peer.id;
	}

	join(peer) {
		const assigned = this.getPeerId(peer);
		peer.ws.send(ProtoMessage(CMD.ID, assigned, this.mesh ? 'true' : ''));
		this.peers.forEach((p) => {
			p.ws.send(ProtoMessage(CMD.PEER_CONNECT, assigned));
			peer.ws.send(ProtoMessage(CMD.PEER_CONNECT, this.getPeerId(p)));
		});
		this.peers.push(peer);
	}

	leave(peer) {
		const idx = this.peers.findIndex((p) => peer === p);
		if (idx === -1) {
			return false;
		}
		const assigned = this.getPeerId(peer);
		const close = assigned === 1;
		this.peers.forEach((p) => {
			if (close) { // Room host disconnected, must close.
				p.ws.close(4000, STR_HOST_DISCONNECTED);
			} else { // Notify peer disconnect.
				p.ws.send(ProtoMessage(CMD.PEER_DISCONNECT, assigned));
			}
		});
		this.peers.splice(idx, 1);
		if (close && this.closeTimer >= 0) {
			// We are closing already.
			clearTimeout(this.closeTimer);
			this.closeTimer = -1;
		}
		return close;
	}

	seal(peer) {
		// Only host can seal
		if (peer.id !== this.host) {
			throw new ProtoError(4000, STR_ONLY_HOST_CAN_SEAL);
		}
		this.sealed = true;
		this.peers.forEach((p) => {
			p.ws.send(ProtoMessage(CMD.SEAL, 0));
		});
		console.log(`Peer ${peer.id} sealed lobby ${this.name} `
			+ `with ${this.peers.length} peers`);
		this.closeTimer = setTimeout(() => {
			// Close peer connection to host (and thus the lobby)
			this.peers.forEach((p) => {
				p.ws.close(1000, STR_SEAL_COMPLETE);
			});
		}, SEAL_CLOSE_TIMEOUT);
	}
}

const lobbies = new Map();
let peersCount = 0;
let waitingLobby = null; // Used for matchmaking

function joinLobby(peer, pLobby, mesh) {
	let lobbyName = pLobby;
	
    // Explicit matchmaking requested via empty string
	if (lobbyName === '') {
        // If there's an open lobby waiting for a match, pair the player
		if (waitingLobby && lobbies.has(waitingLobby) && lobbies.get(waitingLobby).peers.length < 2) {
            lobbyName = waitingLobby;
            waitingLobby = null;
            console.log(`[MATCHMAKING] Peer ${peer.id} paired into waiting lobby ${lobbyName}`);
        } else {
            // Check limitations
            if (lobbies.size >= MAX_LOBBIES) {
                throw new ProtoError(4000, STR_TOO_MANY_LOBBIES);
            }
            if (peer.lobby !== '') {
                throw new ProtoError(4000, STR_ALREADY_IN_LOBBY);
            }
            // Create a new match queue lobby
            lobbyName = randomSecret();
            waitingLobby = lobbyName;
            lobbies.set(lobbyName, new Lobby(lobbyName, peer.id, mesh));
            console.log(`[MATCHMAKING] Peer ${peer.id} created and waiting in lobby ${lobbyName}`);
        }
	} else {
        // Explicit literal lobby name routing (e.g. for playing with friends)
        if (!lobbies.has(lobbyName)) {
            if (lobbies.size >= MAX_LOBBIES) throw new ProtoError(4000, STR_TOO_MANY_LOBBIES);
            if (peer.lobby !== '') throw new ProtoError(4000, STR_ALREADY_IN_LOBBY);
            console.log(`[CUSTOM_MATCH] Peer ${peer.id} created named lobby ${lobbyName}`);
            lobbies.set(lobbyName, new Lobby(lobbyName, peer.id, mesh));
        }
    }

	const lobby = lobbies.get(lobbyName);
	if (!lobby) {
		throw new ProtoError(4000, STR_LOBBY_DOES_NOT_EXISTS);
	}
	if (lobby.sealed) {
		throw new ProtoError(4000, STR_LOBBY_IS_SEALED);
	}
	peer.lobby = lobbyName;
	console.log(`Peer ${peer.id} joining lobby ${lobbyName} `
		+ `with ${lobby.peers.length} peers`);
	lobby.join(peer);
	peer.ws.send(ProtoMessage(CMD.JOIN, 0, lobbyName));
}

function parseMsg(peer, msg) {
	let json = null;
	try {
		json = JSON.parse(msg);
	} catch (e) {
		throw new ProtoError(4000, STR_INVALID_FORMAT);
	}

	const type = typeof (json['type']) === 'number' ? Math.floor(json['type']) : -1;
	const id = typeof (json['id']) === 'number' ? Math.floor(json['id']) : -1;
	const data = typeof (json['data']) === 'string' ? json['data'] : '';

	if (type < 0 || id < 0) {
		throw new ProtoError(4000, STR_INVALID_FORMAT);
	}

	// Lobby joining.
	if (type === CMD.JOIN) {
		joinLobby(peer, data, id === 0);
		return;
	}

	if (!peer.lobby) {
		throw new ProtoError(4000, STR_NEED_LOBBY);
	}
	const lobby = lobbies.get(peer.lobby);
	if (!lobby) {
		throw new ProtoError(4000, STR_SERVER_ERROR);
	}

	// Lobby sealing.
	if (type === CMD.SEAL) {
		lobby.seal(peer);
		return;
	}

	// Message relaying
	if (type === CMD.OFFER || type === CMD.ANSWER || type === CMD.CANDIDATE) {
		let destId = id;
		if (id === 1) {
			destId = lobby.host;
		}
		const dest = lobby.peers.find((e) => e.id === destId);
		if (!dest) {
			throw new ProtoError(4000, STR_INVALID_DEST);
		}
		dest.ws.send(ProtoMessage(type, lobby.getPeerId(peer), data));
		return;
	}
	throw new ProtoError(4000, STR_INVALID_CMD);
}

wss.on('connection', (ws) => {
	if (peersCount >= MAX_PEERS) {
		ws.close(4000, STR_TOO_MANY_PEERS);
		return;
	}
	peersCount++;
	const id = randomId();
	const peer = new Peer(id, ws);
	ws.on('message', (message) => {
		if (typeof message !== 'string') {
            // Buffer to String conversion if Node.js gives buffer
            message = message.toString();
		}
		try {
			parseMsg(peer, message);
		} catch (e) {
			const code = e.code || 4000;
			console.log(`Error parsing message from ${id}:\n${message}`);
			ws.close(code, e.message);
		}
	});
	ws.on('close', (code, reason) => {
		peersCount--;
		console.log(`Connection with peer ${peer.id} closed `
			+ `with reason ${code}: ${reason}`);
		if (peer.lobby && lobbies.has(peer.lobby)) {
            const lobby = lobbies.get(peer.lobby);
            // If the deleted peer was the waiting lobby, clear waiting lobby queue
            if (waitingLobby === peer.lobby) {
                waitingLobby = null;
            }
            if (lobby.leave(peer)) {
                lobbies.delete(peer.lobby);
                console.log(`Deleted lobby ${peer.lobby}`);
            }
			peer.lobby = '';
		}
		if (peer.timeout >= 0) {
			clearTimeout(peer.timeout);
			peer.timeout = -1;
		}
	});
	ws.on('error', (error) => {
		console.error(error);
	});
});

setInterval(() => {
	wss.clients.forEach((ws) => {
		ws.ping();
	});
}, PING_INTERVAL);

server.listen(port, '0.0.0.0', () => {
    console.log(`
🚀 Server active on port ${port}
📦 Serving site from: ${sitePath}
🔒 Cross-Origin Isolation: ACTIVE
    `);
});
