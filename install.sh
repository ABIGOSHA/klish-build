#!/bin/bash
# install.sh - Установка klish на целевое устройство с полной поддержкой YANG/sysrepo
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
    FINAL_DIR=$(find . -maxdepth 1 -type d -name "klish-build-*" | sort | tail -1)
fi

if [ -z "$FINAL_DIR" ]; then
    echo "Ошибка: Не найдена папка с собранным klish."
    echo "Сначала запустите ./build.sh"
    exit 1
fi

echo "Установка klish из $FINAL_DIR"

# --- 1. Установка бинарных файлов klish ---
echo "=== Установка исполняемых файлов ==="
if [ -d "$FINAL_DIR/bin" ]; then
    cp -v "$FINAL_DIR"/bin/* /usr/local/bin/
fi

# --- 2. Установка библиотек klish, libyang, sysrepo ---
echo "=== Установка библиотек ==="
if [ -d "$FINAL_DIR/lib" ]; then
    # Копируем все разделяемые библиотеки
    for lib in "$FINAL_DIR"/lib/*.so*; do
        [ -f "$lib" ] && cp -v "$lib" /usr/local/lib/ 2>/dev/null || true
    done
    # Копируем статические библиотеки
    for lib in "$FINAL_DIR"/lib/*.a; do
        [ -f "$lib" ] && cp -v "$lib" /usr/local/lib/ 2>/dev/null || true
    done
fi

# --- 3. Установка утилит sysrepo (из собранной папки, если есть) ---
echo "=== Установка утилит sysrepo ==="
if [ -f "$FINAL_DIR/bin/sysrepod" ]; then
    cp -v "$FINAL_DIR"/bin/sysrepod /usr/local/bin/
    cp -v "$FINAL_DIR"/bin/sysrepoctl /usr/local/bin/
    cp -v "$FINAL_DIR"/bin/sysrepocfg /usr/local/bin/
elif [ -d "/home/arm/klish-build/src/sysrepo/build/bin" ]; then
    # Если утилиты собраны, но не скопированы в FINAL_DIR
    cp -v /home/arm/klish-build/src/sysrepo/build/bin/sysrepod /usr/local/bin/
    cp -v /home/arm/klish-build/src/sysrepo/build/bin/sysrepoctl /usr/local/bin/
    cp -v /home/arm/klish-build/src/sysrepo/build/bin/sysrepocfg /usr/local/bin/
else
    echo "⚠️  Утилиты sysrepo не найдены, попробуем установить через apt"
    apt update && apt install -y sysrepo sysrepo-plugind 2>/dev/null || true
fi

# --- 4. Установка YANG-моделей ---
echo "=== Установка YANG-моделей ==="
mkdir -p /usr/local/share/yang/modules

# Копируем модели из собранной папки
if [ -d "$FINAL_DIR/share/yang/modules" ]; then
    cp -rv "$FINAL_DIR"/share/yang/modules/* /usr/local/share/yang/modules/ 2>/dev/null || true
fi

# Копируем модели из libyang (если есть)
if [ -d "/home/arm/klish-build/src/libyang/build/install/share/yang/modules" ]; then
    cp -rv /home/arm/klish-build/src/libyang/build/install/share/yang/modules/* /usr/local/share/yang/modules/ 2>/dev/null || true
fi

# Копируем модели из sysrepo (если есть)
if [ -d "/home/arm/klish-build/src/sysrepo/build/install/share/yang/modules" ]; then
    cp -rv /home/arm/klish-build/src/sysrepo/build/install/share/yang/modules/* /usr/local/share/yang/modules/ 2>/dev/null || true
fi

# --- 5. Создание примера YANG-модели для теста ---
echo "=== Создание примера YANG-модели ==="
cat > /tmp/example-interfaces.yang << 'EOF'
module example-interfaces {
    namespace "urn:example:interfaces";
    prefix "exif";

    container interfaces {
        list interface {
            key "name";
            leaf name {
                type string;
            }
            leaf enabled {
                type boolean;
                default true;
            }
            leaf description {
                type string;
            }
        }
    }
}
EOF

# --- 6. Настройка sysrepo (запуск демона и установка моделей) ---
echo "=== Настройка sysrepo ==="

# Запускаем sysrepod, если не запущен
if ! pgrep -x "sysrepod" > /dev/null; then
    echo "Запуск sysrepod..."
    sysrepod -d &
    sleep 2
fi

# Устанавливаем YANG-модели в sysrepo
if command -v sysrepoctl &> /dev/null; then
    echo "Установка YANG-моделей в sysrepo..."
    # Устанавливаем пример интерфейсов
    sysrepoctl -i -g /tmp/example-interfaces.yang -o root -g root 2>/dev/null || true
    
    # Устанавливаем стандартные модели IETF (если есть)
    for yang in /usr/local/share/yang/modules/*.yang; do
        if [ -f "$yang" ]; then
            echo "Установка $(basename "$yang")..."
            sysrepoctl -i -g "$yang" -o root -g root 2>/dev/null || true
        fi
    done
else
    echo "⚠️  sysrepoctl не найден, модели не установлены"
fi

# --- 7. Настройка конфигурации klishd ---
echo "=== Настройка klishd.conf ==="
mkdir -p /etc/klish

# Создаём конфиг для sysrepo
cat > /etc/klish/klishd.conf << 'EOF'
# Основные настройки
UnixSocketPath=/tmp/klishd.sock
UnixSocketMode=0666

# Путь к плагинам
PluginPath=/usr/local/lib

# База данных sysrepo (для YANG-моделей)
DBs=sysrepo
DB.sysrepo.YANGPath=/usr/local/share/yang/modules

# libxml2 (оставляем для обратной совместимости, но отключаем)
# DBs=libxml2
# DB.libxml2.XMLPath=/etc/klish/simple.xml
EOF

# --- 8. Настройка klish.conf для клиента ---
cat > /etc/klish/klish.conf << 'EOF'
UnixSocketPath=/tmp/klishd.sock
Pager="/usr/bin/less -I -F -e -X -K -d -R"
UsePager=y
HistorySize=100
Completion=true
HistoryFile=/tmp/klish_history
EOF

# --- 9. Обновление кэша библиотек ---
echo "=== Обновление кэша библиотек ==="
ldconfig

# --- 10. Создание systemd unit для klishd ---
echo "=== Создание systemd unit для klishd ==="
cat > /etc/systemd/system/klishd.service << 'EOF'
[Unit]
Description=Klish Configuration Daemon
After=network.target sysrepo.service
Wants=sysrepo.service

[Service]
Type=simple
Environment="LD_LIBRARY_PATH=/usr/local/lib"
ExecStart=/usr/local/bin/klishd -d
ExecStartPost=/bin/chmod 666 /tmp/klishd.sock
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# --- 11. Создание systemd unit для sysrepod ---
cat > /etc/systemd/system/sysrepo.service << 'EOF'
[Unit]
Description=Sysrepo Daemon
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/sysrepod -d
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload

# --- 12. Запуск сервисов ---
echo "=== Запуск сервисов ==="
systemctl restart sysrepo.service 2>/dev/null || true
systemctl restart klishd.service 2>/dev/null || true

# --- 13. Проверка установки ---
echo ""
echo "=== ПРОВЕРКА УСТАНОВКИ ==="

# Проверка бинарных файлов
for bin in klish klishd sysrepod sysrepoctl; do
    if command -v $bin &> /dev/null; then
        echo "✅ $bin: $(which $bin)"
    else
        echo "❌ $bin не найден"
    fi
done

# Проверка библиотек
echo ""
echo "Проверка библиотек:"
for lib in libklish.so libsysrepo.so libyang.so; do
    if ldconfig -p | grep -q "$lib"; then
        echo "✅ $lib найден в кэше"
    elif [ -f "/usr/local/lib/$lib" ]; then
        echo "✅ $lib найден (файл присутствует)"
    else
        echo "⚠️  $lib не найден"
    fi
done

# Проверка YANG-моделей
echo ""
echo "YANG-модели в sysrepo:"
if command -v sysrepoctl &> /dev/null; then
    sysrepoctl -l 2>/dev/null | head -10 || echo "  (нет установленных моделей)"
else
    echo "  sysrepoctl не доступен"
fi

# Проверка работы klish
echo ""
echo "=== ГОТОВО ==="
echo ""
echo "Для запуска демона:"
echo "  sudo systemctl start klishd"
echo "  # или"
echo "  sudo klishd -d"
echo ""
echo "Для запуска клиента:"
echo "  klish"
echo ""
echo "Для работы с YANG-моделями:"
echo "  klish"
echo "  > configure"
echo "  [edit] # set interfaces interface eth0 description 'Uplink'"
echo "  [edit] # commit"
echo "  [edit] # show"
echo ""
echo "Для просмотра установленных YANG-моделей:"
echo "  sysrepoctl -l"
echo ""
echo "Для автозапуска при загрузке:"
echo "  sudo systemctl enable klishd"
echo "  sudo systemctl enable sysrepo"