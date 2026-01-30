#!/bin/sh
apk add --no-cache sqlite
sqlite3 /home/node/.n8n/database.sqlite "SELECT id FROM user LIMIT 1;"
