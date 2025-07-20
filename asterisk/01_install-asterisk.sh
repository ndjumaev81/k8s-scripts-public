#!/bin/bash
set -e

LOGFILE=~/install-voice-transcriber.log
exec > >(tee -a "$LOGFILE") 2>&1

export DEBIAN_FRONTEND=noninteractive

# Suppress region prompt (safe default)
echo "libtonezone1:tzcode string 1" | sudo debconf-set-selections

echo ""
echo "🔧 Voice Transcriber Setup Starting: $(date)"
echo "📄 Log file: $LOGFILE"
echo ""

declare -A SUMMARY=(
  ["Asterisk"]="❌ Not installed"
  ["AsteriskConfig"]="❌ Not configured"
)

echo "📦 Updating system..."
sudo apt update -y

echo "📦 Installing dependencies..."
sudo apt install -y wget git build-essential cmake ffmpeg sox curl

# ----- Asterisk Installation -----
if ! command -v asterisk >/dev/null 2>&1; then
  echo "📦 Installing Asterisk from source..."
  cd /usr/src
  sudo wget -N http://downloads.asterisk.org/pub/telephony/asterisk/asterisk-18-current.tar.gz
  sudo tar xvf asterisk-18-current.tar.gz
  cd asterisk-18*/
  sudo contrib/scripts/install_prereq install
  sudo ./configure
  sudo make
  sudo make install
  sudo make samples
  sudo make config
  SUMMARY["Asterisk"]="✅ Installed"
else
  echo "✅ Asterisk already installed"
  SUMMARY["Asterisk"]="✅ Already Installed"
fi

# ----- Asterisk Config -----
PJSIP_CONF=/etc/asterisk/pjsip.conf
EXTENSIONS_CONF=/etc/asterisk/extensions.conf
CONFIGURED=false

if ! grep -q "testuser" "$PJSIP_CONF"; then
  echo "🔧 Adding SIP user to pjsip.conf..."
  sudo tee "$PJSIP_CONF" > /dev/null <<EOF
[transport-udp]
type=transport
protocol=udp
bind=0.0.0.0

[testuser]
type=endpoint
context=default
disallow=all
allow=ulaw
auth=testuser-auth
aors=testuser

[testuser-auth]
type=auth
auth_type=userpass
username=testuser
password=testpass

[testuser]
type=aor
max_contacts=1
EOF
  CONFIGURED=true
fi

if ! grep -q "exten => 1000,1,Answer()" "$EXTENSIONS_CONF"; then
  echo "🔧 Adding dialplan to extensions.conf..."
  sudo tee "$EXTENSIONS_CONF" > /dev/null <<EOF
[default]
exten => 1000,1,Answer()
 same => n,Playback(hello-world)
 same => n,Record(/tmp/recording.wav,5,60)
 same => n,Hangup()
EOF
  CONFIGURED=true
fi

if $CONFIGURED; then
  echo "🔄 Restarting Asterisk..."
  sudo systemctl restart asterisk || echo "⚠️ Asterisk restart may require manual check"
  SUMMARY["AsteriskConfig"]="✅ Applied"
else
  SUMMARY["AsteriskConfig"]="✅ Already Configured"
fi