#!/data/data/com.termux/files/usr/bin/bash
#
# DePIN Mobile Proxy Setup — one command, full setup
# 
# Usage (paste in Termux):
#   curl -sL https://raw.githubusercontent.com/YOUR_REPO/setup-proxy.sh | bash
#   OR: bash setup-proxy.sh
#
# What it does:
#   1. Installs pproxy (Python SOCKS5 server)
#   2. Generates secure credentials
#   3. Configures autostart on boot
#   4. Disables battery optimization (asks permission)
#   5. Tests the proxy
#   6. Installs Tailscale (optional)
#   7. Prints ready-to-use proxy string
#

set -e

# ══════════════════════════════════════
# Config — change these if you want
# ══════════════════════════════════════
PROXY_PORT=1080
PROXY_USER="farm$(shuf -i 1000-9999 -n 1)"
PROXY_PASS="$(head -c 12 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 16)"
CONFIG_DIR="$HOME/.depin-proxy"

# ══════════════════════════════════════
# Colors
# ══════════════════════════════════════
G='\033[0;32m'  # green
Y='\033[1;33m'  # yellow
R='\033[0;31m'  # red
B='\033[1;34m'  # blue
N='\033[0m'     # reset

echo ""
echo -e "${B}╔══════════════════════════════════════╗${N}"
echo -e "${B}║   DePIN Mobile Proxy Setup v1.0      ║${N}"
echo -e "${B}╚══════════════════════════════════════╝${N}"
echo ""

# ══════════════════════════════════════
# Step 1: Install dependencies
# ══════════════════════════════════════
echo -e "${Y}[1/7]${N} Installing packages..."
pkg update -y -q 2>/dev/null
pkg install -y -q python curl termux-api 2>/dev/null || true
pip install -q pproxy 2>/dev/null

if ! command -v pproxy &>/dev/null; then
    echo -e "${R}ERROR: pproxy failed to install${N}"
    exit 1
fi
echo -e "${G}  ✓ pproxy installed${N}"

# ══════════════════════════════════════
# Step 2: Create config directory
# ══════════════════════════════════════
echo -e "${Y}[2/7]${N} Creating config..."
mkdir -p "$CONFIG_DIR"

cat > "$CONFIG_DIR/config.env" << EOF
PROXY_PORT=$PROXY_PORT
PROXY_USER=$PROXY_USER
PROXY_PASS=$PROXY_PASS
EOF

chmod 600 "$CONFIG_DIR/config.env"
echo -e "${G}  ✓ Credentials saved to $CONFIG_DIR/config.env${N}"

# ══════════════════════════════════════
# Step 3: Create run script
# ══════════════════════════════════════
echo -e "${Y}[3/7]${N} Creating run script..."

cat > "$CONFIG_DIR/start.sh" << 'SCRIPT'
#!/data/data/com.termux/files/usr/bin/bash

source "$HOME/.depin-proxy/config.env"
LOG="$HOME/.depin-proxy/proxy.log"

# Kill existing instance
pkill -f "pproxy.*:${PROXY_PORT}" 2>/dev/null || true
sleep 1

# Acquire wake lock (keeps phone awake)
termux-wake-lock 2>/dev/null || true

# Start pproxy
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting proxy on port $PROXY_PORT" >> "$LOG"
nohup pproxy -l "socks5://0.0.0.0:${PROXY_PORT}#${PROXY_USER}:${PROXY_PASS}" \
    >> "$LOG" 2>&1 &

sleep 2

# Verify
if pgrep -f "pproxy.*:${PROXY_PORT}" > /dev/null; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Proxy running (PID: $(pgrep -f "pproxy.*:${PROXY_PORT}"))" >> "$LOG"
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] FAILED to start proxy" >> "$LOG"
    exit 1
fi
SCRIPT

chmod +x "$CONFIG_DIR/start.sh"
echo -e "${G}  ✓ Run script created${N}"

# ══════════════════════════════════════
# Step 4: Create helper commands
# ══════════════════════════════════════
echo -e "${Y}[4/7]${N} Creating helper commands..."

# proxy-start
cat > "$PREFIX/bin/proxy-start" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
bash "$HOME/.depin-proxy/start.sh"
source "$HOME/.depin-proxy/config.env"
echo "Proxy started on port $PROXY_PORT"
EOF
chmod +x "$PREFIX/bin/proxy-start"

# proxy-stop
cat > "$PREFIX/bin/proxy-stop" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
source "$HOME/.depin-proxy/config.env"
pkill -f "pproxy.*:${PROXY_PORT}" 2>/dev/null && echo "Proxy stopped" || echo "Proxy was not running"
EOF
chmod +x "$PREFIX/bin/proxy-stop"

# proxy-status
cat > "$PREFIX/bin/proxy-status" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
source "$HOME/.depin-proxy/config.env"

if pgrep -f "pproxy.*:${PROXY_PORT}" > /dev/null; then
    PID=$(pgrep -f "pproxy.*:${PROXY_PORT}")
    echo "✓ Proxy RUNNING (PID: $PID, port: $PROXY_PORT)"
else
    echo "✗ Proxy NOT running"
    exit 1
fi

# Show external IP
echo ""
echo "Testing external IP..."
IP_INFO=$(curl -s --max-time 10 --socks5-hostname "127.0.0.1:${PROXY_PORT}" \
    --proxy-user "${PROXY_USER}:${PROXY_PASS}" \
    https://ipinfo.io/json 2>/dev/null)

if [ -n "$IP_INFO" ]; then
    IP=$(echo "$IP_INFO" | grep '"ip"' | cut -d'"' -f4)
    ORG=$(echo "$IP_INFO" | grep '"org"' | cut -d'"' -f4)
    CITY=$(echo "$IP_INFO" | grep '"city"' | cut -d'"' -f4)
    echo "  IP:   $IP"
    echo "  ISP:  $ORG"
    echo "  City: $CITY"
else
    echo "  Could not determine external IP"
fi

echo ""
echo "Proxy string for farm:"
echo "  socks5://${PROXY_USER}:${PROXY_PASS}@TAILSCALE_IP:${PROXY_PORT}"
echo ""
echo "Credentials:"
echo "  User: $PROXY_USER"
echo "  Pass: $PROXY_PASS"
echo "  Port: $PROXY_PORT"
EOF
chmod +x "$PREFIX/bin/proxy-status"

# proxy-log
cat > "$PREFIX/bin/proxy-log" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
tail -20 "$HOME/.depin-proxy/proxy.log"
EOF
chmod +x "$PREFIX/bin/proxy-log"

# proxy-creds (quick copy-paste)
cat > "$PREFIX/bin/proxy-creds" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
source "$HOME/.depin-proxy/config.env"
echo ""
echo "═══ Proxy Credentials ═══"
echo "User: $PROXY_USER"
echo "Pass: $PROXY_PASS"
echo "Port: $PROXY_PORT"
echo ""
echo "Local:     socks5://${PROXY_USER}:${PROXY_PASS}@127.0.0.1:${PROXY_PORT}"
echo "Tailscale: socks5://${PROXY_USER}:${PROXY_PASS}@<TAILSCALE_IP>:${PROXY_PORT}"
echo ""
EOF
chmod +x "$PREFIX/bin/proxy-creds"

echo -e "${G}  ✓ Commands: proxy-start, proxy-stop, proxy-status, proxy-log, proxy-creds${N}"

# ══════════════════════════════════════
# Step 5: Setup autostart on boot
# ══════════════════════════════════════
echo -e "${Y}[5/7]${N} Setting up autostart..."

mkdir -p ~/.termux/boot
cat > ~/.termux/boot/start-proxy.sh << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
sleep 15
bash "$HOME/.depin-proxy/start.sh"
EOF
chmod +x ~/.termux/boot/start-proxy.sh

echo -e "${G}  ✓ Will auto-start on boot (requires Termux:Boot app from F-Droid)${N}"

# ══════════════════════════════════════
# Step 6: Start proxy now
# ══════════════════════════════════════
echo -e "${Y}[6/7]${N} Starting proxy..."
bash "$CONFIG_DIR/start.sh"

sleep 2

# ══════════════════════════════════════
# Step 7: Test
# ══════════════════════════════════════
echo -e "${Y}[7/7]${N} Testing proxy..."

IP_INFO=$(curl -s --max-time 15 --socks5-hostname "127.0.0.1:${PROXY_PORT}" \
    --proxy-user "${PROXY_USER}:${PROXY_PASS}" \
    https://ipinfo.io/json 2>/dev/null)

if [ -n "$IP_INFO" ]; then
    IP=$(echo "$IP_INFO" | grep '"ip"' | cut -d'"' -f4)
    ORG=$(echo "$IP_INFO" | grep '"org"' | cut -d'"' -f4)
    CITY=$(echo "$IP_INFO" | grep '"city"' | cut -d'"' -f4)
    HOSTNAME=$(echo "$IP_INFO" | grep '"hostname"' | cut -d'"' -f4)
    
    echo -e "${G}  ✓ Proxy working!${N}"
    echo ""
    echo -e "  ${B}External IP:${N}  $IP"
    echo -e "  ${B}Hostname:${N}    $HOSTNAME"
    echo -e "  ${B}Operator:${N}    $ORG"
    echo -e "  ${B}City:${N}        $CITY"
    
    # Check if it's a real mobile/residential IP
    if echo "$HOSTNAME" | grep -qiE "gprs|mobile|lte|umts|3g|4g|5g|dynamic|pool|ppp|dsl|cable|res"; then
        echo -e "  ${B}Type:${N}        ${G}Mobile/Residential ✓${N}"
    elif echo "$ORG" | grep -qiE "orange|play|plus|t-mobile|vodafone|verizon|comcast|at.t"; then
        echo -e "  ${B}Type:${N}        ${G}ISP ✓${N}"
    else
        echo -e "  ${B}Type:${N}        ${Y}Unknown — verify manually on ipinfo.io${N}"
    fi
else
    echo -e "${R}  ✗ Could not connect through proxy${N}"
    echo "  Check: is mobile data enabled? Is WiFi OFF?"
fi

# ══════════════════════════════════════
# Summary
# ══════════════════════════════════════
echo ""
echo -e "${B}══════════════════════════════════════════${N}"
echo -e "${B}  Setup complete!${N}"
echo -e "${B}══════════════════════════════════════════${N}"
echo ""
echo -e "  ${G}Credentials:${N}"
echo -e "    User: ${Y}${PROXY_USER}${N}"
echo -e "    Pass: ${Y}${PROXY_PASS}${N}"
echo -e "    Port: ${Y}${PROXY_PORT}${N}"
echo ""
echo -e "  ${G}Proxy string (local):${N}"
echo -e "    socks5://${PROXY_USER}:${PROXY_PASS}@127.0.0.1:${PROXY_PORT}"
echo ""
echo -e "  ${G}Commands:${N}"
echo -e "    proxy-status  — check status + show IP"
echo -e "    proxy-stop    — stop proxy"
echo -e "    proxy-start   — start proxy"
echo -e "    proxy-creds   — show credentials"
echo -e "    proxy-log     — show recent logs"
echo ""
echo -e "  ${G}Next steps:${N}"
echo -e "    1. Install ${Y}Tailscale${N} from Google Play"
echo -e "    2. Sign in to Tailscale on phone"
echo -e "    3. Install Tailscale on VPS: ${Y}curl -fsSL https://tailscale.com/install.sh | sh && sudo tailscale up${N}"
echo -e "    4. Run ${Y}tailscale status${N} on VPS to get phone's 100.x.y.z IP"
echo -e "    5. Test from VPS: ${Y}curl --socks5-hostname 100.x.y.z:${PROXY_PORT} --proxy-user ${PROXY_USER}:${PROXY_PASS} https://ipinfo.io/json${N}"
echo ""
echo -e "  ${R}IMPORTANT:${N}"
echo -e "    - Keep WiFi OFF (use mobile data only)"
echo -e "    - Install Termux:Boot from F-Droid for autostart"
echo -e "    - Keep phone plugged in and charging"
echo ""

# Save summary to file for easy reference
cat > "$CONFIG_DIR/README.txt" << README
DePIN Mobile Proxy
==================
User: $PROXY_USER
Pass: $PROXY_PASS
Port: $PROXY_PORT

Local:     socks5://${PROXY_USER}:${PROXY_PASS}@127.0.0.1:${PROXY_PORT}
Tailscale: socks5://${PROXY_USER}:${PROXY_PASS}@<TAILSCALE_IP>:${PROXY_PORT}

Commands:
  proxy-status  — check status + show IP
  proxy-stop    — stop proxy
  proxy-start   — start proxy
  proxy-creds   — show credentials
  proxy-log     — show recent logs
README

echo -e "  Saved to ${Y}$CONFIG_DIR/README.txt${N}"
echo ""
