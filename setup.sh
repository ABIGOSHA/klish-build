#!/bin/bash
# setup.sh - Подготовка окружения: установка системных зависимостей и сборка faux

set -e  # Прерывать выполнение при ошибке

# --- Конфигурация ---
TARGET_ARCH=${TARGET_ARCH:-$(gcc -dumpmachine)}
# Корневая директория для установки собранных зависимостей
PREFIX=$(pwd)/build_root
# Директории для исходников и загрузок
SRC_DIR=$(pwd)/src
DL_DIR=$(pwd)/downloads

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
        # Убедимся, что папка названа именно $dirname
        if [ ! -d "$SRC_DIR/$dirname" ]; then
            local extracted=$(find "$SRC_DIR" -maxdepth 1 -type d -name "$dirname*" | head -1)
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
sudo apt update
sudo apt install -y libxml2-dev libxml2 pkg-config

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
echo "=== Шаг 2: Сборка зависимостей (faux) ==="

# Установка переменных окружения для кросс-компиляции
export CFLAGS="-I$PREFIX/include"
export LDFLAGS="-L$PREFIX/lib"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:$PKG_CONFIG_PATH"
export PATH="$PREFIX/bin:$PATH"

# Сборка faux (нужно запустить autogen.sh, так как это репозиторий без готового configure)
echo "Компиляция faux для $TARGET_ARCH..."
cd "$SRC_DIR/faux"
# Если configure отсутствует, генерируем его через autogen.sh
if [ ! -f configure ]; then
    echo "Запуск autogen.sh для faux..."
    ./autogen.sh
fi
./configure --prefix="$PREFIX" --host="$TARGET_ARCH"
make -j$(nproc)
make install
cd - > /dev/null

echo "=== Подготовка завершена ==="
echo "Системная библиотека libxml2 установлена"
echo "Зависимость faux собрана и установлена в $PREFIX"
echo "Исходники klish-3.2.0 распакованы в $SRC_DIR/klish-3.2.0"
echo "Теперь запустите ./build.sh для сборки klish."