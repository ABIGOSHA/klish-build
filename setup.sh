#!/bin/bash
# setup.sh - Подготовка окружения: установка системных зависимостей и сборка faux

set -e  # Прерывать выполнение при ошибке

# --- Конфигурация ---
TARGET_ARCH=${TARGET_ARCH:-$(gcc -dumpmachine)}
PREFIX=$(pwd)/build_root
SRC_DIR=$(pwd)/src
DL_DIR=$(pwd)/downloads

# Проверка кросс-компиляции
IS_CROSS=0
if [ "$TARGET_ARCH" != "$(gcc -dumpmachine)" ]; then
    IS_CROSS=1
    echo "=== Кросс-компиляция для $TARGET_ARCH ==="
    if ! command -v ${TARGET_ARCH}-gcc &> /dev/null; then
        echo "Ошибка: кросс-компилятор ${TARGET_ARCH}-gcc не найден"
        echo "Установите его, например:"
        echo "  sudo apt install gcc-${TARGET_ARCH}"
        exit 1
    fi
    export CC=${TARGET_ARCH}-gcc
    export CXX=${TARGET_ARCH}-g++
    export AR=${TARGET_ARCH}-ar
    export LD=${TARGET_ARCH}-ld
    export RANLIB=${TARGET_ARCH}-ranlib
fi

# --- Подготовка директорий ---
mkdir -p "$PREFIX"/{bin,lib,include,share}
mkdir -p "$SRC_DIR" "$DL_DIR"

# --- Функции-помощники ---
download_if_needed() {
    local url="$1"
    local filename=$(basename "$url")
    if [ ! -f "$DL_DIR/$filename" ]; then
        echo "Скачивание $filename..."
        wget -q --show-progress "$url" -O "$DL_DIR/$filename"
    else
        echo "Файл $filename уже скачан."
    fi
}

extract_tarball() {
    local archive="$1"
    local dirname="$2"
    if [ ! -d "$SRC_DIR/$dirname" ]; then
        echo "Распаковка $archive в $SRC_DIR/$dirname..."
        tar -xf "$DL_DIR/$archive" -C "$SRC_DIR"
        if [ ! -d "$SRC_DIR/$dirname" ]; then
            local extracted=$(find "$SRC_DIR" -maxdepth 1 -type d -name "$dirname*" | head -1)
            [ -n "$extracted" ] && mv "$extracted" "$SRC_DIR/$dirname"
        fi
    else
        echo "Исходники $dirname уже распакованы."
    fi
}

extract_if_needed() {
    local archive="$1"
    local dirname="$2"
    if [ ! -d "$SRC_DIR/$dirname" ]; then
        echo "Распаковка $archive в $SRC_DIR/$dirname..."
        tar -xf "$DL_DIR/$archive" -C "$SRC_DIR"
        if [ ! -d "$SRC_DIR/$dirname" ]; then
            local extracted=$(find "$SRC_DIR" -maxdepth 1 -type d -name "libxml2-*" | head -1)
            [ -n "$extracted" ] && mv "$extracted" "$SRC_DIR/$dirname"
        fi
    else
        echo "Исходники $dirname уже распакованы."
    fi
}

clone_or_update_repo() {
    local repo_url="$1"
    local target_dir="$2"
    if [ ! -d "$target_dir" ]; then
        echo "Клонирование репозитория $(basename "$repo_url")..."
        git clone "$repo_url" "$target_dir"
    else
        echo "Репозиторий $(basename "$target_dir") уже существует. Обновляем..."
        cd "$target_dir" && git pull && cd - > /dev/null
    fi
}

# --- 0. Установка системных зависимостей ---
echo "=== Шаг 0: Установка системных зависимостей ==="

if [ $IS_CROSS -eq 0 ]; then
    # Нативная сборка
    sudo apt update
    sudo apt install -y libxml2-dev libxml2 pkg-config
else
    # Кросс-компиляция: собираем libxml2 из исходников
    echo "Кросс-компиляция: libxml2 будет собрана из исходников"
    LIBXML2_URL="https://download.gnome.org/sources/libxml2/2.12/libxml2-2.12.6.tar.xz"
    download_if_needed "$LIBXML2_URL"
    extract_if_needed "libxml2-2.12.6.tar.xz" "libxml2-2.12.6"
fi

# --- 1. Скачивание исходных кодов ---
echo "=== Шаг 1: Скачивание исходных кодов ==="

# faux (клонирование репозитория)
FAUX_REPO="https://src.libcode.org/pkun/faux.git"
clone_or_update_repo "$FAUX_REPO" "$SRC_DIR/faux"

# klish (официальный архив)
KLISH_URL="https://src.libcode.org/download/klish/klish-3.2.0.tar.xz"
KLISH_ARCHIVE="klish-3.2.0.tar.xz"
KLISH_DIR="klish-3.2.0"
download_if_needed "$KLISH_URL"
extract_tarball "$KLISH_ARCHIVE" "$KLISH_DIR"

# --- 2. Сборка зависимостей для целевой архитектуры ---
echo "=== Шаг 2: Сборка зависимостей ==="

# Установка переменных окружения
export CFLAGS="-I$PREFIX/include"
export LDFLAGS="-L$PREFIX/lib"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:$PKG_CONFIG_PATH"
export PATH="$PREFIX/bin:$PATH"

# Сборка libxml2 (если кросс-компиляция)
if [ $IS_CROSS -eq 1 ]; then
    echo "Компиляция libxml2 для $TARGET_ARCH..."
    cd "$SRC_DIR/libxml2-2.12.6"
    ./configure --prefix="$PREFIX" --host="$TARGET_ARCH" --without-python --disable-static
    make -j$(nproc)
    make install
    # Проверка успешности
    if [ ! -f "$PREFIX/lib/libxml2.so" ] && [ ! -f "$PREFIX/lib/libxml2.a" ]; then
        echo "Ошибка: libxml2 не собралась"
        exit 1
    fi
    cd - > /dev/null
    echo "✅ libxml2 собрана"
fi

# Сборка faux
echo "Компиляция faux для $TARGET_ARCH..."
cd "$SRC_DIR/faux"
if [ ! -f configure ]; then
    echo "Запуск autogen.sh для faux..."
    ./autogen.sh
fi
./configure --prefix="$PREFIX" --host="$TARGET_ARCH"
make -j$(nproc)
make install
# Проверка успешности
if [ ! -f "$PREFIX/lib/libfaux.so" ] && [ ! -f "$PREFIX/lib/libfaux.a" ]; then
    echo "Ошибка: faux не собралась"
    exit 1
fi
cd - > /dev/null
echo "✅ faux собрана"

echo "=== Подготовка завершена ==="
echo ""
echo "📦 Зависимости собраны и установлены в: $PREFIX"
echo "   - libxml2: $(ls $PREFIX/lib/libxml2.* 2>/dev/null | head -1 || echo 'не найдена')"
echo "   - faux: $(ls $PREFIX/lib/libfaux.* 2>/dev/null | head -1 || echo 'не найдена')"
echo ""
echo "📁 Исходники klish-3.2.0: $SRC_DIR/klish-3.2.0"
echo ""
echo "▶️  Теперь запустите: ./build.sh"