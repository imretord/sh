#!/data/data/com.termux/files/usr/bin/bash
#
# Grass WS Connection Diagnostic
# Тестирует ВСЕ методы подключения к proxy2.wynd.network:4650
# Запуск: bash grass-diag.sh
#

G='\033[0;32m'; R='\033[0;31m'; Y='\033[1;33m'; B='\033[1;34m'; N='\033[0m'
TARGET="proxy2.wynd.network"
PORT=4650
TIMEOUT=12

echo -e "${B}═══ Grass WS Connection Diagnostic ═══${N}"
echo ""

# Ensure deps
pip install -q curl_cffi websockets aiohttp httpx 2>/dev/null

echo -e "${Y}[1/8] Raw TCP${N}"
python3 -c "
import socket, time
try:
    s = socket.create_connection(('$TARGET', $PORT), timeout=$TIMEOUT)
    print('  ✓ TCP connected in', round(time.time() - time.time() + 0.01, 3), 's')
    s.close()
except Exception as e:
    print(f'  ✗ {e}')
" 2>&1

echo ""
echo -e "${Y}[2/8] Python ssl (stdlib) — TLS handshake${N}"
python3 -c "
import socket, ssl, time
t0 = time.time()
try:
    s = socket.create_connection(('$TARGET', $PORT), timeout=$TIMEOUT)
    ctx = ssl.create_default_context()
    ss = ctx.wrap_socket(s, server_hostname='$TARGET')
    print(f'  ✓ TLS OK in {time.time()-t0:.2f}s — {ss.version()}')
    ss.close()
except Exception as e:
    print(f'  ✗ {time.time()-t0:.2f}s — {type(e).__name__}: {e}')
" 2>&1

echo ""
echo -e "${Y}[3/8] curl CLI — wss upgrade${N}"
timeout $TIMEOUT curl -sS -o /dev/null -w "HTTP %{http_code} in %{time_total}s\n" \
    --include \
    -H "Connection: Upgrade" \
    -H "Upgrade: websocket" \
    -H "Sec-WebSocket-Version: 13" \
    -H "Sec-WebSocket-Key: dGVzdGtleQ==" \
    -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" \
    -H "Origin: chrome-extension://lkbnfiajjmbhnfledhphioinpickokdi" \
    "https://$TARGET:$PORT/" 2>&1 | while read line; do echo "  $line"; done
RES=$?
[ $RES -eq 124 ] && echo -e "  ${R}✗ Timeout${N}"

echo ""
echo -e "${Y}[4/8] curl_cffi — HTTP impersonate (no WS)${N}"
timeout $TIMEOUT python3 -c "
from curl_cffi.requests import Session
import time
t0 = time.time()
try:
    s = Session(impersonate='chrome120')
    r = s.get('https://$TARGET:$PORT/',
        headers={'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120.0.0.0'},
        timeout=$TIMEOUT)
    print(f'  ✓ HTTP {r.status_code} in {time.time()-t0:.2f}s')
except Exception as e:
    print(f'  ✗ {time.time()-t0:.2f}s — {type(e).__name__}: {e}')
" 2>&1

echo ""
echo -e "${Y}[5/8] curl_cffi — WS connect (chrome120)${N}"
timeout $TIMEOUT python3 -c "
from curl_cffi.requests import Session
import time
t0 = time.time()
try:
    s = Session(impersonate='chrome120')
    ws = s.ws_connect('wss://$TARGET:$PORT/',
        headers={
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120.0.0.0 Safari/537.36',
            'Origin': 'chrome-extension://lkbnfiajjmbhnfledhphioinpickokdi'
        })
    print(f'  ✓ CONNECTED in {time.time()-t0:.2f}s')
    ws.close()
except Exception as e:
    print(f'  ✗ {time.time()-t0:.2f}s — {type(e).__name__}: {e}')
" 2>&1

echo ""
echo -e "${Y}[6/8] websockets lib (Python ssl)${N}"
timeout $TIMEOUT python3 -c "
import asyncio, time
async def test():
    t0 = time.time()
    try:
        import websockets
        ws = await asyncio.wait_for(
            websockets.connect('wss://$TARGET:$PORT/',
                additional_headers={
                    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120.0.0.0 Safari/537.36',
                    'Origin': 'chrome-extension://lkbnfiajjmbhnfledhphioinpickokdi'
                }),
            timeout=$TIMEOUT)
        print(f'  ✓ CONNECTED in {time.time()-t0:.2f}s')
        await ws.close()
    except Exception as e:
        print(f'  ✗ {time.time()-t0:.2f}s — {type(e).__name__}: {e}')
asyncio.run(test())
" 2>&1

echo ""
echo -e "${Y}[7/8] aiohttp WS (Python ssl)${N}"
timeout $TIMEOUT python3 -c "
import aiohttp, asyncio, time
async def test():
    t0 = time.time()
    try:
        async with aiohttp.ClientSession() as session:
            ws = await asyncio.wait_for(
                session.ws_connect('wss://$TARGET:$PORT/',
                    headers={
                        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120.0.0.0 Safari/537.36',
                        'Origin': 'chrome-extension://lkbnfiajjmbhnfledhphioinpickokdi'
                    }),
                timeout=$TIMEOUT)
            print(f'  ✓ CONNECTED in {time.time()-t0:.2f}s')
            await ws.close()
    except Exception as e:
        print(f'  ✗ {time.time()-t0:.2f}s — {type(e).__name__}: {e}')
asyncio.run(test())
" 2>&1

echo ""
echo -e "${Y}[8/8] openssl s_client — raw TLS (no Python)${N}"
echo -e "GET / HTTP/1.1\r\nHost: $TARGET\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGVzdA==\r\nSec-WebSocket-Version: 13\r\nOrigin: chrome-extension://lkbnfiajjmbhnfledhphioinpickokdi\r\n\r\n" | \
timeout $TIMEOUT openssl s_client -connect "$TARGET:$PORT" -servername "$TARGET" -quiet 2>&1 | head -5 | while read line; do echo "  $line"; done
RES=$?
[ $RES -eq 124 ] && echo -e "  ${R}✗ Timeout${N}"

echo ""
echo -e "${B}═══ Summary ═══${N}"
echo "If ALL methods fail — Grass blocks this entire IP/ASN on port 4650"
echo "If only Python ssl fails but curl/openssl works — TLS fingerprint detection"
echo "If curl_cffi WS works — use curl_cffi in grass.py (solution found)"
echo "If only openssl works — need custom TLS config"
echo ""
echo -e "Exit IP for reference:"
curl -sS --max-time 5 https://ipinfo.io/json 2>/dev/null | grep -E '"ip"|"org"|"hostname"' | while read line; do echo "  $line"; done
echo ""
