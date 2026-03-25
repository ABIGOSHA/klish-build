#!/bin/bash
# build.sh - Компиляция klish

set -e

# --- Конфигурация ---
PREFIX=$(pwd)/build_root
TARGET_ARCH=${TARGET_ARCH:-$(gcc -dumpmachine)}
BUILD_DIR=$(pwd)/build_output
CONFIG_DIR=$(pwd)/config_output
FINAL_DIR=$(pwd)/klish-build-$(date +%Y%m%d)-$TARGET_ARCH

echo "=== Сборка klish ==="
echo "Целевая архитектура: $TARGET_ARCH"
echo "Корень зависимостей: $PREFIX"
echo "Итоговая папка: $FINAL_DIR"

mkdir -p "$BUILD_DIR" "$CONFIG_DIR" "$FINAL_DIR"
mkdir -p "$(pwd)/config"

# --- Создание конфигурационных файлов для klish ---
echo "=== Создание конфигурационных файлов для klish ==="

# klish.conf
cat > "$(pwd)/config/klish.conf" << 'EOF'
UnixSocketPath=/tmp/klishd.sock
Pager="/usr/bin/less -I -F -e -X -K -d -R"
UsePager=y
HistorySize=100
Completion=true
HistoryFile=/tmp/klish_history
EOF

# klishd.conf
cat > "$(pwd)/config/klishd.conf" << 'EOF'
UnixSocketPath=/tmp/klishd.sock
UnixSocketMode=0666

DBs=libxml2
DB.libxml2.XMLPath=/etc/klish/simple.xml
PluginPath=/usr/local/lib
EOF

# simple.xml
cat > "$(pwd)/config/simple.xml" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<KLISH
        xmlns="https://klish.libcode.org/klish3"
        xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
        xsi:schemaLocation="https://src.libcode.org/pkun/klish/src/master/klish.xsd">

<PLUGIN name="klish"/>

<PLUGIN name="script"/>


<PTYPE name="STRING">
        <ACTION sym="STRING@klish"/>
</PTYPE>


<VIEW name="main">

<HOTKEY key="^Z" cmd="exit"/>

<PROMPT name="prompt">
        <ACTION sym="prompt">%u@%h&gt; </ACTION>
</PROMPT>

<COMMAND name="exit" help="Exit view">
        <ACTION sym="nav">pop</ACTION>
        <ACTION sym="printl">Exiting klish session</ACTION>
</COMMAND>

<COMMAND name="cmd" help="Clear settings">
        <COMMAND name="first" help="Clear settings"/>
        <ACTION sym="printl">test</ACTION>
</COMMAND>

<COMMAND name="comm" value="command" help="Clear settings">
        <ACTION sym="printl">test2</ACTION>
</COMMAND>

<COMMAND name="ls" help="List path">
        <PARAM name="path" ptype="/STRING" help="Path"/>
        <ACTION sym="script">
        echo "$KLISH_COMMAND"
        ls "$KLISH_PARAM_path"
        </ACTION>
</COMMAND>

<COMMAND name="pytest" help="Test for Python script">
        <ACTION sym="script">#!/usr/bin/python3
import os
print('ENV', os.getenv("KLISH_COMMAND"))
        </ACTION>
</COMMAND>

</VIEW>

</KLISH>
EOF

echo "✅ Конфигурационные файлы klish созданы в папке config/"

# --- Настройка окружения для кросс-компиляции ---
IS_CROSS=0
if [ "$TARGET_ARCH" != "$(gcc -dumpmachine)" ]; then
    IS_CROSS=1
    echo "=== Кросс-компиляция активна ==="
    
    if ! command -v ${TARGET_ARCH}-gcc &> /dev/null; then
        echo "Ошибка: кросс-компилятор ${TARGET_ARCH}-gcc не найден"
        exit 1
    fi
    
    export CC=${TARGET_ARCH}-gcc
    export CXX=${TARGET_ARCH}-g++
    export AR=${TARGET_ARCH}-ar
    export LD=${TARGET_ARCH}-ld
    export RANLIB=${TARGET_ARCH}-ranlib
fi

# --- Пути к библиотекам (все зависимости в $PREFIX) ---
export CFLAGS="-I$PREFIX/include"
export LDFLAGS="-L$PREFIX/lib"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
export PATH="$PREFIX/bin:$PATH"

# --- Проверка наличия зависимостей ---
if [ ! -f "$PREFIX/lib/libfaux.so" ] && [ ! -f "$PREFIX/lib/libfaux.a" ]; then
    echo "Ошибка: библиотека faux не найдена в $PREFIX"
    echo "Сначала запустите ./setup.sh"
    exit 1
fi

if [ ! -f "$PREFIX/lib/libxml2.so" ] && [ ! -f "$PREFIX/lib/libxml2.a" ]; then
    echo "Ошибка: библиотека libxml2 не найдена в $PREFIX"
    echo "Сначала запустите ./setup.sh"
    exit 1
fi

# --- Сборка klish ---
echo ""
echo "=== Сборка klish ==="
cd "$(pwd)/src/klish-3.2.0"

echo "Конфигурация klish..."
./configure --prefix="$BUILD_DIR" \
            --host="$TARGET_ARCH" \
            --with-faux="$PREFIX" \
            --with-libxml2="$PREFIX" \
            --sysconfdir="$CONFIG_DIR/etc"

echo "Компиляция klish..."
make -j$(nproc)

echo "Установка klish..."
make install

cd - > /dev/null
echo "✅ klish собран"

# --- Формирование итогового пакета ---
echo ""
echo "=== Формирование итогового пакета ==="

# Копируем klish
cp -r "$BUILD_DIR"/* "$FINAL_DIR/"

# Копирование конфигурации klish из папки config
if [ -d "$(pwd)/config" ]; then
    echo "Копирование конфигурации klish..."
    mkdir -p "$FINAL_DIR/etc/klish"
    cp -rv "$(pwd)/config/klish.conf" "$FINAL_DIR/etc/klish/" 2>/dev/null || true
    cp -rv "$(pwd)/config/klishd.conf" "$FINAL_DIR/etc/klish/" 2>/dev/null || true
    cp -rv "$(pwd)/config/simple.xml" "$FINAL_DIR/etc/klish/" 2>/dev/null || true
fi

# --- Создание скриптов для запуска ---
cat > "$FINAL_DIR/run_klishd.sh" << 'EOF'
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export KLISH_CONF="$SCRIPT_DIR/etc/klish"
export LD_LIBRARY_PATH="$SCRIPT_DIR/lib:$LD_LIBRARY_PATH"
exec "$SCRIPT_DIR/bin/klishd" "$@"
EOF
chmod +x "$FINAL_DIR/run_klishd.sh"

cat > "$FINAL_DIR/run_klish.sh" << 'EOF'
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export KLISH_CONF="$SCRIPT_DIR/etc/klish"
export LD_LIBRARY_PATH="$SCRIPT_DIR/lib:$LD_LIBRARY_PATH"
exec "$SCRIPT_DIR/bin/klish" "$@"
EOF
chmod +x "$FINAL_DIR/run_klish.sh"

# Скрипт для установки FreeRADIUS (если нужен на целевом устройстве)
cat > "$FINAL_DIR/install_radius.sh" << 'EOF'
#!/bin/bash
# install_radius.sh - Установка FreeRADIUS на целевое устройство
# Запускать с правами root

if [ "$EUID" -ne 0 ]; then
    echo "Пожалуйста, запустите с sudo: sudo ./install_radius.sh"
    exit 1
fi

echo "=== Установка FreeRADIUS ==="
apt update
apt install -y freeradius freeradius-mysql freeradius-utils

# Копирование конфигурации, если есть
if [ -d "$(dirname "$0")/etc/freeradius" ]; then
    echo "Копирование конфигурации FreeRADIUS..."
    cp -rv "$(dirname "$0")/etc/freeradius"/* /etc/freeradius/3.0/
fi

echo "=== FreeRADIUS установлен ==="
echo "Для запуска: sudo systemctl start freeradius"
echo "Для теста: radtest testuser testpass localhost 0 testing123"
EOF
chmod +x "$FINAL_DIR/install_radius.sh"

echo "=== Сборка завершена ==="
echo "Итоговый пакет: $FINAL_DIR"
echo ""
echo "Для запуска демона klish:"
echo "  cd $FINAL_DIR && ./run_klishd.sh"
echo ""
echo "Для запуска клиента klish:"
echo "  cd $FINAL_DIR && ./run_klish.sh"
echo ""
echo "Для установки FreeRADIUS на целевом устройстве:"
echo "  cd $FINAL_DIR && sudo ./install_radius.sh"
echo ""
echo "Для установки klish в систему:"
echo "  sudo ./install.sh"