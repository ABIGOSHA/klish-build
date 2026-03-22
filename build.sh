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
echo "Корень зависимостей: $PREFIX"
echo "Итоговая папка: $FINAL_DIR"

mkdir -p "$BUILD_DIR" "$CONFIG_DIR" "$FINAL_DIR"

# --- Настройка окружения для кросс-компиляции ---
# Проверяем, идёт ли кросс-компиляция
IS_CROSS=0
if [ "$TARGET_ARCH" != "$(gcc -dumpmachine)" ]; then
    IS_CROSS=1
    echo "=== Кросс-компиляция активна ==="
    
    # Проверяем наличие кросс-компилятора
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

# --- Пути к библиотекам ---
export CFLAGS="-I$PREFIX/include"
export LDFLAGS="-L$PREFIX/lib"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"

# Для нативной сборки добавляем системные пути
if [ $IS_CROSS -eq 0 ]; then
    export CFLAGS="$CFLAGS -I/usr/include/libxml2"
    export PKG_CONFIG_PATH="$PKG_CONFIG_PATH:/usr/lib/x86_64-linux-gnu/pkgconfig"
fi

export PATH="$PREFIX/bin:$PATH"

# --- Проверка наличия faux ---
if [ ! -f "$PREFIX/lib/libfaux.so" ] && [ ! -f "$PREFIX/lib/libfaux.a" ]; then
    echo "Ошибка: библиотека faux не найдена в $PREFIX"
    echo "Сначала запустите ./setup.sh"
    exit 1
fi

# --- Переход в исходники klish ---
cd "$(pwd)/src/klish-3.2.0"

# --- Конфигурация klish ---
echo "Конфигурация klish..."
./configure --prefix="$BUILD_DIR" \
            --host="$TARGET_ARCH" \
            --with-faux="$PREFIX" \
            --sysconfdir="$CONFIG_DIR/etc"

# --- Компиляция ---
echo "Компиляция..."
make -j$(nproc)

# --- Установка ---
echo "Установка..."
make install

cd - > /dev/null

# --- Формирование итогового пакета ---
echo "=== Формирование итогового пакета ==="
cp -r "$BUILD_DIR"/* "$FINAL_DIR/"

# Копирование конфигурации из репозитория klish-config (если есть)
if [ -d "$(pwd)/config" ]; then
    echo "Копирование конфигурации из папки config..."
    mkdir -p "$FINAL_DIR/etc/klish"
    cp -rv "$(pwd)/config"/* "$FINAL_DIR/etc/klish/"
elif [ -d "$(pwd)/src/klish-3.2.0/conf" ]; then
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

# --- Создание скриптов для запуска ---
cat > "$FINAL_DIR/run_klishd.sh" << EOF
#!/bin/bash
SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
export KLISH_CONF="\$SCRIPT_DIR/etc/klish"
export LD_LIBRARY_PATH="\$SCRIPT_DIR/lib:\$LD_LIBRARY_PATH"
"\$SCRIPT_DIR/bin/klishd" "\$@"
EOF
chmod +x "$FINAL_DIR/run_klishd.sh"

cat > "$FINAL_DIR/run_klish.sh" << EOF
#!/bin/bash
SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
export KLISH_CONF="\$SCRIPT_DIR/etc/klish"
export LD_LIBRARY_PATH="\$SCRIPT_DIR/lib:\$LD_LIBRARY_PATH"
"\$SCRIPT_DIR/bin/klish" "\$@"
EOF
chmod +x "$FINAL_DIR/run_klish.sh"

echo "=== Сборка завершена ==="
echo "Итоговый пакет: $FINAL_DIR"
echo ""
echo "Для запуска демона:"
echo "  cd $FINAL_DIR && ./run_klishd.sh"
echo ""
echo "Для запуска клиента:"
echo "  cd $FINAL_DIR && ./run_klish.sh"
echo ""
echo "Для установки в систему:"
echo "  sudo ./install.sh"