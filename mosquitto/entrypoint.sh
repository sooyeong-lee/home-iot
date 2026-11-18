#!/bin/sh
# MQTT 계정 파일을 환경 변수로 만들고 mosquitto 실행
set -e
: "${MQTT_USERNAME:?MQTT_USERNAME 필요}"
: "${MQTT_PASSWORD:?MQTT_PASSWORD 필요}"
mkdir -p /mosquitto/data
rm -f /mosquitto/data/passwd
mosquitto_passwd -c -b /mosquitto/data/passwd "$MQTT_USERNAME" "$MQTT_PASSWORD"
chown -R mosquitto:mosquitto /mosquitto/data
chmod 0700 /mosquitto/data/passwd
exec mosquitto -c /mosquitto/config/mosquitto.conf
