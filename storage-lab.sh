#!/usr/bin/env bash
set -Eeuo pipefail

# Ubuntu: sudo bash storage-lab.sh [base|minimum]
# Создаёт новую лабораторную. Существующие ресурсы не переиспользуются.
fail() {
    printf 'Ошибка: %s\n' "$*" >&2
    exit 1
}

mode="${1:-base}"
if (( $# > 1 )) || [[ "$mode" != base && "$mode" != minimum ]]; then
    fail 'Использование: sudo bash storage-lab.sh [base|minimum]'
fi

[[ "$(uname -s)" == Linux ]] || fail 'Нужна Linux-машина с поддержкой loop, MD RAID и LVM.'
(( EUID == 0 )) || fail 'Запустите скрипт через sudo bash storage-lab.sh.'

commands=(dd mkdir losetup mdadm mkfs.ext4 mount mountpoint find flock cat df)
if [[ "$mode" == base ]]; then
    commands+=(pvcreate vgcreate lvcreate pvs vgs lvs)
fi
for command_name in "${commands[@]}"; do
    command -v "$command_name" >/dev/null 2>&1 ||
        fail "Не найдена команда $command_name. Установите mdadm, lvm2, e2fsprogs и util-linux."
done

exec 9>/run/lock/sysadmin-storage-lab.lock
flock -n 9 || fail 'Другой экземпляр storage-lab.sh уже работает.'

lab_dir=/mnt/raid-lab
raid_device=/dev/md0
raid_mount=/mnt/raid
logs_mount=/mnt/logs

[[ ! -e "$lab_dir" && ! -L "$lab_dir" ]] ||
    fail "$lab_dir уже существует. Используйте чистую учебную машину; образы не перезаписаны."
[[ ! -e "$raid_device" && ! -L "$raid_device" && ! -e /sys/block/md0 ]] ||
    fail "$raid_device уже существует. Существующий массив не изменён."

mount_dirs=("$raid_mount")
if [[ "$mode" == base ]]; then
    vg_names=$(vgs --noheadings -o vg_name)
    if [[ "$vg_names" =~ (^|[[:space:]])vg_data($|[[:space:]]) ]]; then
        fail 'Группа vg_data уже существует. Существующие тома не изменены.'
    fi
    [[ ! -e /dev/vg_data && ! -L /dev/vg_data ]] ||
        fail '/dev/vg_data уже существует.'
    mount_dirs+=("$logs_mount")
fi

for target in "${mount_dirs[@]}"; do
    [[ ! -L "$target" ]] || fail "$target является символической ссылкой."
    if [[ -e "$target" ]]; then
        [[ -d "$target" ]] || fail "$target не является каталогом."
        if mountpoint -q "$target"; then
            fail "$target уже используется как точка монтирования."
        fi
        first_entry=$(find "$target" -mindepth 1 -maxdepth 1 -print -quit)
        [[ -z "$first_entry" ]] || fail "$target содержит файлы."
    fi
done

# При сбое сохраняем образы и уже созданные ресурсы для диагностики.
# Автоматического удаления, форматирования при повторе или отката нет.
trap 'printf "Ошибка на строке %s. Созданные ресурсы оставлены для диагностики в %s. Не запускайте скрипт повторно поверх них.\n" "$LINENO" "$lab_dir" >&2' ERR

mkdir -m 700 "$lab_dir"
for target in "${mount_dirs[@]}"; do
    mkdir -p "$target"
done

dd if=/dev/zero of="$lab_dir/disk1.img" bs=1M count=512 status=progress
dd if=/dev/zero of="$lab_dir/disk2.img" bs=1M count=512 status=progress

# --show возвращает фактический номер свободного устройства, включая loop3+.
loop_a=$(losetup --find --show --nooverlap --partscan "$lab_dir/disk1.img")
printf 'disk1.img: %s\n' "$loop_a" >> "$lab_dir/devices.txt"
loop_b=$(losetup --find --show --nooverlap --partscan "$lab_dir/disk2.img")
printf 'disk2.img: %s\n' "$loop_b" >> "$lab_dir/devices.txt"
cat "$lab_dir/devices.txt"

# --run убирает вопрос mdadm: здесь используются только что созданные
# нулевые образы, а не существующие диски с данными. --force не применяется.
mdadm --create "$raid_device" --level=1 --raid-devices=2 --run "$loop_a" "$loop_b"
mkfs.ext4 "$raid_device"
mount "$raid_device" "$raid_mount"

if [[ "$mode" == base ]]; then
    dd if=/dev/zero of="$lab_dir/disk3.img" bs=1M count=512 status=progress
    loop_c=$(losetup --find --show --nooverlap --partscan "$lab_dir/disk3.img")
    printf 'disk3.img: %s\n' "$loop_c" >> "$lab_dir/devices.txt"
    printf 'disk3.img: %s\n' "$loop_c"

    pvcreate "$loop_c"
    vgcreate vg_data "$loop_c"
    lvcreate -L 200M -n lv_logs vg_data
    mkfs.ext4 /dev/vg_data/lv_logs
    mount /dev/vg_data/lv_logs "$logs_mount"
fi

printf '\n=== Loop-устройства лабораторной ===\n'
cat "$lab_dir/devices.txt"
printf '\n=== RAID 1 ===\n'
cat /proc/mdstat
mdadm --detail "$raid_device"
df -hT "$raid_mount"

if [[ "$mode" == base ]]; then
    printf '\n=== LVM ===\n'
    pvs "$loop_c"
    vgs vg_data
    lvs -o lv_name,vg_name,lv_size,devices vg_data
    df -hT "$logs_mount"
fi

printf '\nГотово. Ресурсы созданы для текущей загрузки Linux; автоподключение не настроено.\n'
