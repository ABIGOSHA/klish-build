#!/bin/bash
# setup.sh - Подготовка окружения: сборка libxml2, faux, libyang, sysrepo и установка FreeRADIUS

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

# --- 0. Установка системных зависимостей для сборки ---
echo "=== Шаг 0: Установка инструментов сборки и зависимостей ==="

# Устанавливаем инструменты сборки и зависимости для libyang/sysrepo
sudo apt update
sudo apt install -y build-essential git wget pkg-config autoconf automake libtool \
    libtalloc-dev libssl-dev libpam0g-dev libmysqlclient-dev libpq-dev libsqlite3-dev \
    cmake doxygen python3-dev python3-pip swig libpcre2-dev libcurl4-openssl-dev \
    freeradius freeradius-mysql freeradius-utils

# --- 1. Скачивание исходных кодов ---
echo "=== Шаг 1: Скачивание исходных кодов ==="

# libxml2 (всегда собираем из исходников)
LIBXML2_URL="https://download.gnome.org/sources/libxml2/2.12/libxml2-2.12.6.tar.xz"
download_if_needed "$LIBXML2_URL"
extract_if_needed "libxml2-2.12.6.tar.xz" "libxml2-2.12.6"

# faux (клонирование репозитория)
FAUX_REPO="https://src.libcode.org/pkun/faux.git"
clone_or_update_repo "$FAUX_REPO" "$SRC_DIR/faux"

# klish (официальный архив)
KLISH_URL="https://src.libcode.org/download/klish/klish-3.2.0.tar.xz"
KLISH_ARCHIVE="klish-3.2.0.tar.xz"
KLISH_DIR="klish-3.2.0"
download_if_needed "$KLISH_URL"
extract_tarball "$KLISH_ARCHIVE" "$KLISH_DIR"

# libyang (парсер YANG)
LIBYANG_REPO="https://github.com/CESNET/libyang.git"
clone_or_update_repo "$LIBYANG_REPO" "$SRC_DIR/libyang"

# sysrepo (хранилище конфигурации)
SYSREPO_REPO="https://github.com/sysrepo/sysrepo.git"
clone_or_update_repo "$SYSREPO_REPO" "$SRC_DIR/sysrepo"

# --- 2. Сборка зависимостей для целевой архитектуры ---
echo "=== Шаг 2: Сборка зависимостей (libxml2, faux, libyang, sysrepo) ==="

# Установка переменных окружения
export CFLAGS="-I$PREFIX/include"
export LDFLAGS="-L$PREFIX/lib"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:$PKG_CONFIG_PATH"
export PATH="$PREFIX/bin:$PATH"

# Сборка libxml2
echo "Компиляция libxml2 для $TARGET_ARCH..."
cd "$SRC_DIR/libxml2-2.12.6"
./configure --prefix="$PREFIX" --host="$TARGET_ARCH" --without-python --disable-static
make -j$(nproc)
make install
if [ ! -f "$PREFIX/lib/libxml2.so" ] && [ ! -f "$PREFIX/lib/libxml2.a" ]; then
    echo "Ошибка: libxml2 не собралась"
    exit 1
fi
cd - > /dev/null
echo "✅ libxml2 собрана"

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
if [ ! -f "$PREFIX/lib/libfaux.so" ] && [ ! -f "$PREFIX/lib/libfaux.a" ]; then
    echo "Ошибка: faux не собралась"
    exit 1
fi
cd - > /dev/null
echo "✅ faux собрана"

# Сборка libyang
echo "Компиляция libyang для $TARGET_ARCH..."
cd "$SRC_DIR/libyang"
mkdir -p build && cd build
cmake -DCMAKE_INSTALL_PREFIX="$PREFIX" \
      -DCMAKE_C_COMPILER="${CC:-gcc}" \
      -DCMAKE_CXX_COMPILER="${CXX:-g++}" \
      -DCMAKE_SYSTEM_NAME=Linux \
      -DCMAKE_C_FLAGS="$CFLAGS" \
      -DCMAKE_CXX_FLAGS="$CFLAGS" \
      -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS" \
      -DCMAKE_SHARED_LINKER_FLAGS="$LDFLAGS" \
      -DCMAKE_MODULE_LINKER_FLAGS="$LDFLAGS" \
      -DENABLE_BUILD_TESTS=OFF \
      -DENABLE_BUILD_TOOLS=ON ..
make -j$(nproc)
make install
cd - > /dev/null
echo "✅ libyang собрана"

# Сборка sysrepo
echo "Компиляция sysrepo для $TARGET_ARCH..."
cd "$SRC_DIR/sysrepo"
mkdir -p build && cd build
cmake -DCMAKE_INSTALL_PREFIX=/home/arm/klish-build/build_root \
      -DCMAKE_C_COMPILER=gcc \
      -DCMAKE_CXX_COMPILER=g++ \
      -DCMAKE_SYSTEM_NAME=Linux \
      -DGEN_LANGUAGE_BINDINGS=ON \
      -DGEN_CPP_BINDINGS=ON \
      -DENABLE_TESTS=OFF \
      -DENABLE_CACHE=ON \
      -DPRINTED_CONTEXT_ADDRESS=1 ..
make -j$(nproc)
make install
cd - > /dev/null
echo "✅ sysrepo собрана"

# Обновление кэша библиотек (для нативной сборки)
if [ $IS_CROSS -eq 0 ]; then
    sudo ldconfig
fi

echo "=== Подготовка завершена ==="
echo ""
echo "📦 Зависимости собраны и установлены в: $PREFIX"
echo "   - libxml2: $(ls $PREFIX/lib/libxml2.* 2>/dev/null | head -1 || echo 'не найдена')"
echo "   - faux: $(ls $PREFIX/lib/libfaux.* 2>/dev/null | head -1 || echo 'не найдена')"
echo "   - libyang: $(ls $PREFIX/lib/libyang.* 2>/dev/null | head -1 || echo 'не найдена')"
echo "   - sysrepo: $(ls $PREFIX/lib/libsysrepo.* 2>/dev/null | head -1 || echo 'не найдена')"
echo ""
echo "📦 FreeRADIUS установлен через apt:"
echo "   - $(freeradius -v 2>/dev/null | head -1 || echo 'проверьте установку')"
echo ""
echo "📁 Исходники:"
echo "   - klish-3.2.0: $SRC_DIR/klish-3.2.0"
echo "   - libyang: $SRC_DIR/libyang"
echo "   - sysrepo: $SRC_DIR/sysrepo"
echo ""
echo "▶️  Теперь запустите: ./build.sh"