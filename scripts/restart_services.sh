#!/usr/bin/env bash
# Restarts ALL services and removes ALL unprocessed audio
source /etc/birdnet/birdnet.conf
set -x
my_dir=$HOME/BirdNET-Pi/scripts


sudo systemctl stop birdnet_recording.service livestream.service

# Identify the BirdNET user
TARGET_USER="${BIRDNET_USER}"
if [ -z "${TARGET_USER}" ]; then
  TARGET_USER=$(awk -F: '/1000/ {print $1}' /etc/passwd)
fi

# Terminate existing PulseAudio instances to prevent duplicates/locks
if [ -n "${TARGET_USER}" ]; then
  sudo -u "${TARGET_USER}" pulseaudio -k 2>/dev/null || true
  sleep 1
  if pgrep -u "${TARGET_USER}" pulseaudio &>/dev/null; then
    sudo pkill -9 -u "${TARGET_USER}" pulseaudio 2>/dev/null || true
  fi
fi

services=(chart_viewer.service
  spectrogram_viewer.service
  icecast2.service
  livestream.service
  birdnet_recording.service
  birdnet_analysis.service
  birdnet_log.service
  birdnet_stats.service)

for i in  "${services[@]}";do
  sudo systemctl restart "${i}"
done

for i in {1..5}; do
  # We want to loop here (5*5seconds) until the critical services are running
  if systemctl is-active --quiet birdnet_recording.service && \
     systemctl is-active --quiet livestream.service && \
     systemctl is-active --quiet birdnet_analysis.service; then
      logger "[$0] Critical audio and analysis services are running"
      break
  fi

  sleep 5
done

# Verify vital services and report error if unable to return system to working state
for service in birdnet_recording.service livestream.service birdnet_analysis.service; do
  if ! systemctl is-active --quiet "$service"; then
    logger -s -p user.err "[$0] ERROR: $service failed to start or is inactive after restart!"
  fi
done
