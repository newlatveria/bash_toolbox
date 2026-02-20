#!/bin/bash

if docker compose version &>/dev/null; then
    COMPOSE="docker compose"
elif docker-compose version &>/dev/null; then
    COMPOSE="docker-compose"
else
    echo "Docker Compose not installed."
    exit 1
fi

open_browser() {
    URL="http://localhost:5050"
    if command -v xdg-open &>/dev/null; then
        xdg-open $URL
    elif command -v open &>/dev/null; then
        open $URL
    fi
}

menu() {
while true; do
    clear
    echo "Agent Zero Control Panel"
    echo "1) Start Stack"
    echo "2) Stop Stack"
    echo "3) Status"
    echo "4) Pull Models"
    echo "5) Open Dashboard"
    echo "0) Exit"
    read -p "Select Option: " opt

    case $opt in
        1)
            $COMPOSE up -d
            sleep 3
            open_browser
            ;;
        2) $COMPOSE down ;;
        3) docker ps ;;
        4)
            docker exec ollama ollama pull llama3
            docker exec ollama ollama pull nomic-embed-text
            ;;
        5) open_browser ;;
        0) exit ;;
    esac

    read -p "Press Enter to continue..."
done
}

if [[ $# -eq 0 ]]; then
    menu
else
    case "$1" in
        start) $COMPOSE up -d && sleep 3 && open_browser ;;
        stop) $COMPOSE down ;;
        status) docker ps ;;
        models)
            docker exec ollama ollama pull llama3
            docker exec ollama ollama pull nomic-embed-text
            ;;
    esac
fi
