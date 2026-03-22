#!/bin/bash
# install.sh - Установка klish на целевое устройство
# Запускать с правами root

set -e

if [ "$EUID" -ne 0 ]; then
    echo "Пожалуйста, запустите с sudo: sudo ./install.sh"
    exit 1
fi

# Поиск последней собранной папки
FINAL_DIR=$(find . -maxdepth 1 -type d -name "klish-build-*" | sort | tail -1)
if [ -z "$FINAL_DIR" ]; then
    echo "Не найдена папка с собранным klish. Сначала запустите ./build.sh"
    exit 1
fi

echo "Установка klish из $FINAL_DIR"

# Копирование бинарных файлов (klish и klishd в bin)
if [ -d "$FINAL_DIR/bin" ]; then
    echo "Копирование исполняемых файлов..."
    cp -v "$FINAL_DIR"/bin/* /usr/local/bin/
fi

# Копирование библиотек
if [ -d "$FINAL_DIR/lib" ]; then
    echo "Копирование библиотек..."
    cp -v "$FINAL_DIR"/lib/* /usr/local/lib/
    ldconfig
fi

# Копирование конфигурации
if [ -d "$FINAL_DIR/etc/klish" ]; then
    echo "Копирование конфигурации в /etc/klish..."
    mkdir -p /etc/klish
    cp -rv "$FINAL_DIR"/etc/klish/* /etc/klish/
fi

# Создание systemd unit для автозапуска klishd
if [ -f /usr/local/bin/klishd ] && [ ! -f /etc/systemd/system/klishd.service ]; then
    echo "Создание systemd unit для klishd..."
    cat > /etc/systemd/system/klishd.service << EOF
[Unit]
Description=Klish Configuration Daemon
After=network.target

[Service]
ExecStart=/usr/local/bin/klishd
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    echo "Для автозапуска выполните: systemctl enable klishd"
fi

echo "=== Установка завершена ==="