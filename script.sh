#!/usr/bin/env bash

username="${1:-}"

user_dir="$HOME/sysadmin-users/$username"

mkdir -p "$user_dir"

echo "# Bash configuration for $username" > "$user_dir/.bashrc"

echo "Привет, $username!"
echo "Создан каталог: $user_dir"
