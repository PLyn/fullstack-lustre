#!/bin/bash

ROOT_DIR="$(pwd)"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

SERVER_PID=""
FIFO="/tmp/gleam_watch_$$"

cleanup() {
    echo -e "\n${YELLOW}Shutting down...${NC}"
    [ -e "$FIFO" ] && exec 3<&-
    stop_server
    rm -f "$FIFO"
    pkill -P $$ inotifywait 2>/dev/null
    exit 0
}

stop_server() {
    echo -e "${YELLOW}Clearing port 3000...${NC}"
    if [ ! -z "$SERVER_PID" ]; then
        # Kill the process group
        kill -TERM -$SERVER_PID 2>/dev/null || true
    fi
    if command -v fuser &> /dev/null; then
        fuser -k 3000/tcp 2>/dev/null || true
    fi
    sleep 0.4
}

build_and_run() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}Building client...${NC}"

    cd "$ROOT_DIR/client" || return
    if gleam run -m lustre/dev build --outdir=../server/priv/static; then
        echo -e "${GREEN}✓ Client built successfully${NC}"
    else
        echo -e "${RED}✗ Client build failed${NC}"
        cd "$ROOT_DIR"
        return 1
    fi

    echo -e "${BLUE}Starting server...${NC}"
    cd "$ROOT_DIR/server" || return

    set -m
    gleam run &
    SERVER_PID=$!
    set +m

    echo -e "${GREEN}✓ Server started (PID: $SERVER_PID)${NC}"
    cd "$ROOT_DIR"
}

trap cleanup SIGINT SIGTERM EXIT

# 1. Clear and create FIFO
rm -f "$FIFO"
mkfifo "$FIFO"

# 2. Check for dependencies
if ! command -v inotifywait &> /dev/null; then
    echo -e "${RED}Error: inotifywait is not installed${NC}"
    exit 1
fi

# 3. Start the watcher BEFORE opening the file descriptor
# This ensures there is a writer ready so the 'exec' doesn't hang
inotifywait -m -r -e modify,create,delete,move \
    --format '%w%f' \
    "$ROOT_DIR/client/src" \
    "$ROOT_DIR/server/src" \
    "$ROOT_DIR/shared/src" > "$FIFO" 2>/dev/null &

# 4. Open FIFO for reading on FD 3
exec 3<"$FIFO"

# 5. Run initial build
build_and_run

LAST_CHANGE=0
DEBOUNCE_SECONDS=1

echo -e "${GREEN}Watching for changes...${NC}"

# 6. Main Loop
while read -u 3 -r line; do
    CURRENT_TIME=$(date +%s)
    if [ $((CURRENT_TIME - LAST_CHANGE)) -ge $DEBOUNCE_SECONDS ]; then
        echo -e "\n${BLUE}Change detected: $line${NC}"
        stop_server
        build_and_run
        LAST_CHANGE=$CURRENT_TIME
    fi
done
