#!/bin/bash

APP_NAME="cub_server"
RESULT_DIR="vtune_run_$(date -u +%Y%m%d_%H%M%S)"
PID=$(pgrep -n "$APP_NAME")

if [ -z "$PID" ]; then
  echo "❌ '$APP_NAME' 프로세스를 찾을 수 없습니다."
  exit 1
fi

# mkdir -p $RESULT_DIR

# 1. VTune paused 상태로 시작
prlimit --nofile=1048576:1048576 \
vtune -collect hotspots \
  -knob sampling-mode=hw \
  -knob enable-stack-collection=true \
  -knob stack-size=4096 \
  -start-paused \
  -target-pid $PID \
  -r "$RESULT_DIR" &

VTUNE_PID=$!

# 2. 요청 직전 수집 시작
sleep 5
vtune -command resume -r "$RESULT_DIR"

# 3. 요청 처리
csql -u dba demodb -i run.sql

# 4. 수집 중단
vtune -command stop -r "$RESULT_DIR"

echo vtune -report summary -r "$RESULT_DIR" 
echo vtune -report hotspots -r "$RESULT_DIR"
echo vtune -report callstacks -r "$RESULT_DIR"

# 5. (선택) VTune 프로세스 종료 (보통 필요 없음)
kill -INT $VTUNE_PID

# 종료까지 대기 (선택)
wait $VTUNE_PID

