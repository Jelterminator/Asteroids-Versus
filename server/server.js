const express = require('express');
const http = require('http');
const WebSocket = require('ws');
const path = require('path');
const compression = require('compression');

/**
 * Asteroids Versus - Unified Signaling & Static Server
 * Implements Cross-Origin Isolation (COOP/COEP) for Godot 4 SharedArrayBuffer support.
 */

const app = express();
const port = process.env.PORT || 8080;

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

let waitingPlayer = null;

wss.on('connection', (ws) => {
    console.log('New peer connected');

    ws.on('message', (message) => {
        let msg;
        try {
            msg = JSON.parse(message);
        } catch (e) {
            return;
        }

        if (msg.type === 'join') {
            if (!waitingPlayer) {
                waitingPlayer = ws;
                ws.send(JSON.stringify({ type: 'waiting' }));
            } else {
                const player1 = waitingPlayer;
                const player2 = ws;
                waitingPlayer = null;

                player1.partner = player2;
                player2.partner = player1;

                player1.send(JSON.stringify({ type: 'match_found', is_host: true }));
                player2.send(JSON.stringify({ type: 'match_found', is_host: false }));
                console.log('Handshake: Match created');
            }
        } else if (ws.partner) {
            // Forward signaling messages (SDP/ICE)
            ws.partner.send(message.toString());
        }
    });

    ws.on('close', () => {
        if (waitingPlayer === ws) {
            waitingPlayer = null;
        }
        if (ws.partner) {
            ws.partner.send(JSON.stringify({ type: 'partner_disconnected' }));
            ws.partner.partner = null;
        }
    });
});

server.listen(port, '0.0.0.0', () => {
    console.log(`
🚀 Server active on port ${port}
📦 Serving site from: ${sitePath}
🔒 Cross-Origin Isolation: ACTIVE
    `);
});
