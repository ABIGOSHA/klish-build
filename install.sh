#!/bin/bash
# install.sh - Установка klish на целевое устройство
# Запускать с правами root

set -e

if [ "$EUID" -ne 0 ]; then
    echo "Пожалуйста, запустите с sudo: sudo ./install.sh"
    exit 1
fi

# --- Определение архитектуры ---
TARGET_ARCH=${TARGET_ARCH:-$(gcc -dumpmachine)}
echo "Целевая архитектура: $TARGET_ARCH"

# --- Поиск последней собранной папки ---
FINAL_DIR=$(find . -maxdepth 1 -type d -name "klish-build-*" | grep "$TARGET_ARCH" | sort | tail -1)

if [ -z "$FINAL_DIR" ]; then
    # Если папка с архитектурой не найдена, ищем любую
    FINAL_DIR=$(find . -maxdepth 1 -type d -name "klish-build-*" | sort | tail -1)
fi

if [ -z "$FINAL_DIR" ]; then
    echo "Ошибка: Не найдена папка с собранным klish."
    echo "Сначала запустите ./build.sh"
    exit 1
fi

echo "Установка klish из $FINAL_DIR"

# --- Бэкап существующих конфигов (опционально) ---
BACKUP_DIR="/root/klish_backup_$(date +%Y%m%d_%H%M%S)"
if [ -d "/etc/klish" ] && [ "$(ls -A /etc/klish 2>/dev/null)" ]; then
    echo "Создание бэкапа существующей конфигурации в $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"
    cp -r /etc/klish "$BACKUP_DIR/"
fi

# --- Копирование бинарных файлов ---
if [ -d "$FINAL_DIR/bin" ]; then
    echo "Копирование исполняемых файлов..."
    cp -v "$FINAL_DIR"/bin/* /usr/local/bin/
fi

# --- Копирование библиотек ---
if [ -d "$FINAL_DIR/lib" ]; then
    echo "Копирование библиотек..."
    cp -v "$FINAL_DIR"/lib/* /usr/local/lib/
    
    # Обновляем кэш библиотек
    echo "Обновление кэша библиотек..."
    ldconfig
fi

# --- Копирование конфигурации ---
if [ -d "$FINAL_DIR/etc/klish" ]; then
    echo "Копирование конфигурации в /etc/klish..."
    mkdir -p /etc/klish
    
    # Копируем, но не перезаписываем существующие файлы, если не указано иное
    if [ "$OVERWRITE_CONFIG" = "yes" ]; then
        cp -rv "$FINAL_DIR"/etc/klish/* /etc/klish/
    else
        cp -rvn "$FINAL_DIR"/etc/klish/* /etc/klish/ 2>/dev/null || true
        echo "Примечание: существующие файлы конфигурации сохранены."
        echo "Для перезаписи установите переменную OVERWRITE_CONFIG=yes"
    fi
fi

# --- Настройка прав доступа к сокету в конфиге ---
if [ -f "/etc/klish/klishd.conf" ]; then
    # Убеждаемся, что сокет создаётся с правильными правами
    if ! grep -q "UnixSocketMode=0666" /etc/klish/klishd.conf; then
        echo "Добавление UnixSocketMode=0666 в конфиг..."
        echo "UnixSocketMode=0666" >> /etc/klish/klishd.conf
    fi
fi

# --- Создание systemd unit для автозапуска ---
if [ -f /usr/local/bin/klishd ]; then
    if [ ! -f /etc/systemd/system/klishd.service ]; then
        echo "Создание systemd unit для klishd..."
        cat > /etc/systemd/system/klishd.service << EOF
[Unit]
Description=Klish Configuration Daemon
After=network.target

[Service]
ExecStart=/usr/local/bin/klishd
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        echo ""
        echo "Для автозапуска выполните: systemctl enable klishd"
        echo "Для запуска сейчас: systemctl start klishd"
    else
        echo "systemd unit уже существует. Для пересоздания удалите:"
        echo "  sudo rm /etc/systemd/system/klishd.service"
    fi
fi

# --- Проверка установки ---
echo ""
echo "=== Проверка установки ==="
if command -v klishd &> /dev/null; then
    echo "✅ klishd: $(which klishd)"
else
    echo "❌ klishd не найден в PATH"
fi

if command -v klish &> /dev/null; then
    echo "✅ klish: $(which klish)"
else
    echo "❌ klish не найден в PATH"
fi

echo ""
echo "=== Установка завершена ==="
echo ""
echo "Для запуска демона:"
echo "  sudo klishd -d"
echo ""
echo "Для запуска клиента:"
echo "  klish"
echo ""
echo "Для автозапуска при загрузке:"
echo "  sudo systemctl enable klishd"
echo "  sudo systemctl start klishd"