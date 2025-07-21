#!/bin/bash
set -e

LOGFILE=~/update-asterisk-config.log
exec > >(tee -a "$LOGFILE") 2>&1

echo ""
echo "🔧 Asterisk Config Update: $(date)"
echo "📄 Log file: $LOGFILE"
echo ""

PJSIP_CONF=/etc/asterisk/pjsip.conf
EXTENSIONS_CONF=/etc/asterisk/extensions.conf
UPDATED=false

echo "🔍 Checking and applying pjsip.conf..."

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

UPDATED=true
echo "✅ pjsip.conf updated"

echo "🔍 Checking and applying extensions.conf..."

sudo tee "$EXTENSIONS_CONF" > /dev/null <<EOF
[default]
exten => s,1,Answer()
 same => n,Playback(hello-world) ; built-in prompt
 same => n,Wait(1)
 same => n,Playback(beep)
 same => n,Record(/var/spool/asterisk/recordings/recording.wav,5,30,k)
 same => n,Playback(vm-goodbye)
 same => n,Hangup()
EOF

UPDATED=true
echo "✅ extensions.conf updated"

if $UPDATED; then
  echo "🔄 Reloading Asterisk dialplan and config..."
  sudo asterisk -rx "core reload"
  sudo asterisk -rx "dialplan reload"
  echo "✅ Asterisk reloaded"
else
  echo "ℹ️ No updates made"
fi
