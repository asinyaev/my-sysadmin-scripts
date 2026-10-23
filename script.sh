#!/usr/bin/env bash

if [[ $# -ne 1 ]]; then
    echo "Ошибка: укажите имя пользователя" >&2
    echo "Пример: ./script.sh alex" >&2
    exit 1
fi

username="$1"

base_dir="$HOME/sysadmin-users"
user_dir="$base_dir/$username"
log_file="$HOME/sysadmin-setup.log"

if [[ -e "$user_dir" ]]; then
    echo "Ошибка: каталог уже существует: $user_dir" >&2
    exit 1
fi

mkdir -p "$base_dir"
mkdir "$user_dir"

printf '# Bash configuration for %s\nalias ll="ls -lah"\n' \
    "$username" > "$user_dir/.bashrc"

printf '%s | Created directory for %s: %s\n' \
    "$(date '+%Y-%m-%d %H:%M:%S')" \
    "$username" \
    "$user_dir" >> "$log_file"

echo "Привет, $username!"
echo "Создан каталог: $user_dir"
echo "Создан файл: $user_dir/.bashrc"
echo "Запись добавлена в лог: $log_file"
