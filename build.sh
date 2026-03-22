#!/bin/bash
# build.sh - Компиляция официального klish-3.2.0

set -e

# --- Конфигурация ---
PREFIX=$(pwd)/build_root
TARGET_ARCH=${TARGET_ARCH:-$(gcc -dumpmachine)}
BUILD_DIR=$(pwd)/build_output
CONFIG_DIR=$(pwd)/config_output
FINAL_DIR=$(pwd)/klish-build-$(date +%Y%m%d)-$TARGET_ARCH

echo "=== Сборка klish ==="
echo "Целевая архитектура: $TARGET_ARCH"
echo "Корень зависимостей (faux): $PREFIX"
echo "Итоговая папка: $FINAL_DIR"

mkdir -p "$BUILD_DIR" "$CONFIG_DIR" "$FINAL_DIR"

# Пути к системной libxml2
export CFLAGS="-I$PREFIX/include -I/usr/include/libxml2"
export LDFLAGS="-L$PREFIX/lib"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:/usr/lib/x86_64-linux-gnu/pkgconfig"
export PATH="$PREFIX/bin:$PATH"

# Переход в исходники официального klish
cd "$(pwd)/src/klish-3.2.0"

# Конфигурация klish
echo "Конфигурация klish..."
./configure --prefix="$BUILD_DIR" \
            --host="$TARGET_ARCH" \
            --with-faux="$PREFIX" \
            --sysconfdir="$CONFIG_DIR/etc"

echo "Компиляция..."
make -j$(nproc)

echo "Установка..."
make install

cd - > /dev/null

# --- Формирование итогового пакета ---
echo "=== Формирование итогового пакета ==="
cp -r "$BUILD_DIR"/* "$FINAL_DIR/"

# Копирование конфигурации, если она есть в исходниках klish
if [ -d "$(pwd)/src/klish-3.2.0/conf" ]; then
    echo "Копирование конфигурации из исходников klish..."
    mkdir -p "$FINAL_DIR/etc"
    cp -r "$(pwd)/src/klish-3.2.0/conf" "$FINAL_DIR/etc/klish"
elif [ -d "$CONFIG_DIR/etc/klish" ]; then
    echo "Копирование конфигурации из временной установки..."
    cp -r "$CONFIG_DIR/etc/klish" "$FINAL_DIR/etc/"
else
    echo "ВНИМАНИЕ: Конфигурация klish не найдена."
    echo "Создаю пустую папку etc/klish для ручного заполнения."
    mkdir -p "$FINAL_DIR/etc/klish"
fi

# Создание скрипта для запуска
cat > "$FINAL_DIR/run_klishd.sh" << EOF
#!/bin/bash
export KLISH_CONF="\$(dirname \$0)/etc/klish"
export LD_LIBRARY_PATH="\$(dirname \$0)/lib:$LD_LIBRARY_PATH"
"\$(dirname \$0)/bin/klishd" "\$@"
EOF
chmod +x "$FINAL_DIR/run_klishd.sh"

echo "=== Сборка завершена ==="
echo "Итоговый пакет: $FINAL_DIR"
echo "Для запуска демона используйте: cd $FINAL_DIR && ./run_klishd.sh"