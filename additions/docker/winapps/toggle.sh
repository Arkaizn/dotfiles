#!/usr/bin/env bash

COMPOSE="-f /home/arkaizn/docker/winapps/compose.yml"

# check for any running containers in this project
if [ -n "$(docker compose $COMPOSE ps --filter status=running -q)" ]; then
  echo "⚙️  Services are up – stopping them..."
  docker compose $COMPOSE stop
else
  echo "⚙️  Services are down – starting them..."
  docker compose $COMPOSE up -d
fi
