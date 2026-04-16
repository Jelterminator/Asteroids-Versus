const WebSocket = require('ws');
const http = require('http');

const port = process.env.PORT || 8080;
const server = http.createServer();
const wss = new WebSocket.Server({ server });

let waitingPlayer = null;

wss.on('connection', (ws) => {
    console.log('New connection');

    ws.on('message', (message) => {
        let msg;
        try {
            msg = JSON.parse(message);
        } catch (e) {
            console.error('Invalid JSON:', message);
            return;
        }

        if (msg.type === 'join') {
            if (!waitingPlayer) {
                waitingPlayer = ws;
                ws.send(JSON.stringify({ type: 'waiting' }));
                console.log('Player waiting...');
            } else {
                const player1 = waitingPlayer;
                const player2 = ws;
                waitingPlayer = null;

                player1.partner = player2;
                player2.partner = player1;

                player1.send(JSON.stringify({ type: 'match_found', is_host: true }));
                player2.send(JSON.stringify({ type: 'match_found', is_host: false }));
                console.log('Match found!');
            }
        } else if (ws.partner) {
            // Forward signaling messages (SDP, ICE) to the partner
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
        console.log('Connection closed');
    });
});

server.listen(port, '0.0.0.0', () => {
    console.log(`Signaling server listening on port ${port}`);
});
