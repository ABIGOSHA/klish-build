#!/bin/bash
# build_all.sh - Полная автоматическая сборка всех компонентов
# Поддерживает кросс-компиляцию через переменную TARGET_ARCH

set -e

echo "=== ПОЛНАЯ АВТОМАТИЧЕСКАЯ СБОРКА KLISH + SYSREPO ==="

# --- Конфигурация ---
TARGET_ARCH=${TARGET_ARCH:-$(gcc -dumpmachine)}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="$SCRIPT_DIR/build_root"
SRC_DIR="$SCRIPT_DIR/src"
FINAL_DIR="$SCRIPT_DIR/klish-build-$(date +%Y%m%d)-$TARGET_ARCH"

# Определяем, идёт ли кросс-компиляция
IS_CROSS=0
if [ "$TARGET_ARCH" != "$(gcc -dumpmachine)" ]; then
    IS_CROSS=1
    echo "=== Кросс-компиляция для $TARGET_ARCH ==="
    if ! command -v ${TARGET_ARCH}-gcc &> /dev/null; then
        echo "Ошибка: кросс-компилятор ${TARGET_ARCH}-gcc не найден"
        echo "Установите его, например: sudo apt install gcc-${TARGET_ARCH}"
        exit 1
    fi
    export CC=${TARGET_ARCH}-gcc
    export CXX=${TARGET_ARCH}-g++
    export AR=${TARGET_ARCH}-ar
    export LD=${TARGET_ARCH}-ld
    export RANLIB=${TARGET_ARCH}-ranlib
fi

echo "Целевая архитектура: $TARGET_ARCH"
echo "Итоговая папка: $FINAL_DIR"

mkdir -p "$PREFIX"/{bin,lib,include,share}
mkdir -p "$SRC_DIR"
mkdir -p "$FINAL_DIR"/{bin,lib,etc/klish,share/yang/modules}

# --- Установка системных зависимостей (только для нативной сборки) ---
if [ $IS_CROSS -eq 0 ]; then
    echo ""
    echo "=== Шаг 1: Установка системных зависимостей ==="
    sudo apt update
    sudo apt install -y build-essential git wget pkg-config autoconf automake libtool \
        cmake doxygen python3-dev swig libpcre2-dev libcurl4-openssl-dev
fi

# --- Функция для клонирования/обновления репозитория ---
clone_or_update() {
    local repo_url="$1"
    local target_dir="$2"
    if [ ! -d "$SRC_DIR/$target_dir" ]; then
        echo "Клонирование $repo_url..."
        git clone "$repo_url" "$SRC_DIR/$target_dir"
    else
        echo "Обновление $target_dir..."
        cd "$SRC_DIR/$target_dir" && git pull && cd - > /dev/null
    fi
}

# --- Функция для скачивания и распаковки архива ---
download_tarball() {
    local url="$1"
    local dirname="$2"
    local archive=$(basename "$url")
    local extracted_dir=$(echo "$archive" | sed 's/\.tar\..*$//')
    
    if [ ! -d "$SRC_DIR/$dirname" ]; then
        cd "$SRC_DIR"
        if [ ! -f "$archive" ]; then
            echo "Скачивание $archive..."
            wget -q --show-progress "$url"
        else
            echo "Файл $archive уже скачан"
        fi
        echo "Распаковка $archive..."
        tar -xf "$archive"
        rm -f "$archive"
        
        # Переименовываем папку, если нужно
        if [ "$extracted_dir" != "$dirname" ] && [ -d "$extracted_dir" ]; then
            mv "$extracted_dir" "$dirname"
        fi
        cd - > /dev/null
    else
        echo "Исходники $dirname уже распакованы"
    fi
}

# --- Клонирование и скачивание исходников ---
echo ""
echo "=== Шаг 2: Подготовка исходников ==="

download_tarball "https://src.libcode.org/download/faux/faux-2.2.0.tar.xz" "faux"
download_tarball "https://download.gnome.org/sources/libxml2/2.12/libxml2-2.12.6.tar.xz" "libxml2"
download_tarball "https://github.com/CESNET/libyang/archive/refs/tags/v4.2.2.tar.gz" "libyang-4.2.2"
download_tarball "https://github.com/sysrepo/sysrepo/archive/refs/tags/v4.2.10.tar.gz" "sysrepo-4.2.10"
download_tarball "https://src.libcode.org/download/klish/klish-3.1.0.tar.xz" "klish"
download_tarball "https://src.libcode.org/pkun/klish-plugin-sysrepo/archive/3.1.0.tar.gz" "klish-plugin-sysrepo"

# --- Настройка окружения для сборки ---
export CFLAGS="-I$PREFIX/include"
export LDFLAGS="-L$PREFIX/lib"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:$PKG_CONFIG_PATH"
export PATH="$PREFIX/bin:$PATH"

# --- Сборка faux ---
echo ""
echo "=== Шаг 3: Сборка faux ==="
cd "$SRC_DIR/faux"
./configure --prefix="$PREFIX" --host="$TARGET_ARCH"
make -j$(nproc)
make install

# --- Сборка libxml2 ---
echo ""
echo "=== Шаг 4: Сборка libxml2 ==="
cd "$SRC_DIR/libxml2"
./configure --prefix="$PREFIX" --host="$TARGET_ARCH" --without-python --disable-static
make -j$(nproc)
make install

# --- Сборка libyang ---
echo ""
echo "=== Шаг 5: Сборка libyang ==="
cd "$SRC_DIR/libyang-4.2.2"
mkdir -p build && cd build
cmake -DCMAKE_INSTALL_PREFIX="$PREFIX" \
      -DCMAKE_C_COMPILER="${CC:-gcc}" \
      -DCMAKE_CXX_COMPILER="${CXX:-g++}" \
      -DENABLE_BUILD_TESTS=OFF \
      -DENABLE_BUILD_TOOLS=ON ..
make -j$(nproc)
make install

# --- Сборка sysrepo ---
echo ""
echo "=== Шаг 6: Сборка sysrepo ==="
cd "$SRC_DIR/sysrepo-4.2.10"
mkdir -p build && cd build
cmake -DCMAKE_INSTALL_PREFIX="$PREFIX" \
      -DCMAKE_C_COMPILER="${CC:-gcc}" \
      -DCMAKE_CXX_COMPILER="${CXX:-g++}" \
      -DGEN_LANGUAGE_BINDINGS=ON \
      -DGEN_CPP_BINDINGS=ON \
      -DENABLE_TESTS=OFF \
      -DENABLE_CACHE=ON \
      -DPRINTED_CONTEXT_ADDRESS=1 \
      -DSYSREPO_PRINTED_CONTEXT_ADDRESS=1 ..
make -j$(nproc)
make install

# --- Сборка klish ---
echo ""
echo "=== Шаг 7: Сборка klish ==="
cd "$SRC_DIR/klish"
./configure --prefix="$PREFIX" \
            --host="$TARGET_ARCH" \
            --with-faux="$PREFIX" \
            --with-libxml2="$PREFIX"
make -j$(nproc)
make install

# --- Сборка klish-plugin-sysrepo ---
echo ""
echo "=== Шаг 8: Сборка klish-plugin-sysrepo ==="
cd "$SRC_DIR/klish-plugin-sysrepo"
./autogen.sh
./configure --prefix="$PREFIX" \
            --host="$TARGET_ARCH" \
            --with-faux="$PREFIX" \
            --with-libyang="$PREFIX" \
            --with-sysrepo="$PREFIX" \
            --with-klish="$PREFIX" \
            CFLAGS="-I$PREFIX/include" \
            LDFLAGS="-L$PREFIX/lib"
make -j$(nproc)
make install

# --- Формирование итогового пакета ---
echo ""
echo "=== Шаг 9: Формирование итогового пакета ==="

# Копируем бинарные файлы
cp -r "$PREFIX/bin/"* "$FINAL_DIR/bin/" 2>/dev/null || true
cp -r "$PREFIX/sbin/"* "$FINAL_DIR/bin/" 2>/dev/null || true

# Копируем библиотеки
cp -r "$PREFIX/lib/"*.so* "$FINAL_DIR/lib/" 2>/dev/null || true
cp -r "$PREFIX/lib/"*.a "$FINAL_DIR/lib/" 2>/dev/null || true

# Копируем YANG-модели
if [ -d "$PREFIX/share/yang/modules" ]; then
    cp -r "$PREFIX/share/yang/modules/"* "$FINAL_DIR/share/yang/modules/" 2>/dev/null || true
fi

# Копируем пример YANG-модели для теста
cat > "$FINAL_DIR/share/yang/modules/example-interfaces.yang" << 'EOF'
module example-interfaces {
    namespace "urn:example:interfaces";
    prefix "exif";
    container interfaces {
        list interface {
            key "name";
            leaf name { type string; }
            leaf enabled { type boolean; default true; }
            leaf description { type string; }
        }
    }
}
EOF

# --- Создание конфигурации klishd ---
cat > "$FINAL_DIR/etc/klish/klishd.conf" << 'EOF'
UnixSocketPath=/tmp/klishd.sock
UnixSocketMode=0666

# Основная база данных - sysrepo (для YANG)
DBs=sysrepo
DB.sysrepo.YANGPath=./share/yang/modules

# Резервная база - libxml2 (для обратной совместимости)
# DBs=libxml2
# DB.libxml2.XMLPath=/etc/klish/simple.xml

PluginPath=./lib
EOF

cat > "$FINAL_DIR/etc/klish/klish.conf" << 'EOF'
UnixSocketPath=/tmp/klishd.sock
Pager="/usr/bin/less -I -F -e -X -K -d -R"
UsePager=y
HistorySize=100
Completion=true
HistoryFile=/tmp/klish_history
EOF

# --- Создание скриптов запуска ---
cat > "$FINAL_DIR/run_sysrepod.sh" << 'EOF'
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export LD_LIBRARY_PATH="$SCRIPT_DIR/lib:$LD_LIBRARY_PATH"
exec "$SCRIPT_DIR/bin/sysrepod" -d "$@"
EOF
chmod +x "$FINAL_DIR/run_sysrepod.sh"

cat > "$FINAL_DIR/run_klishd.sh" << 'EOF'
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export KLISH_CONF="$SCRIPT_DIR/etc/klish"
export LD_LIBRARY_PATH="$SCRIPT_DIR/lib:$LD_LIBRARY_PATH"
export SYSREPO_PATH="$SCRIPT_DIR/share/yang/modules"
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

# --- Скрипт для установки YANG-моделей в sysrepo ---
cat > "$FINAL_DIR/install_yang_models.sh" << 'EOF'
#!/bin/bash
if [ "$EUID" -ne 0 ]; then
    echo "Пожалуйста, запустите с sudo: sudo ./install_yang_models.sh"
    exit 1
fi

YANG_DIR="$(dirname "$0")/share/yang/modules"
for yang in "$YANG_DIR"/*.yang; do
    [ -f "$yang" ] || continue
    echo "Установка $(basename "$yang")..."
    sysrepoctl -i -g "$yang" -a 2>/dev/null || echo "  (уже установлена или ошибка)"
done
EOF
chmod +x "$FINAL_DIR/install_yang_models.sh"

# --- Статистика ---
echo ""
echo "=== СБОРКА ЗАВЕРШЕНА ==="
echo "Итоговый пакет: $FINAL_DIR"
echo ""
echo "📊 Статистика:"
echo "   - Бинарные файлы: $(ls -1 "$FINAL_DIR/bin" 2>/dev/null | wc -l)"
echo "   - Библиотеки: $(ls -1 "$FINAL_DIR/lib" 2>/dev/null | wc -l)"
echo "   - YANG-модели: $(ls -1 "$FINAL_DIR/share/yang/modules" 2>/dev/null | wc -l)"
echo ""
echo "🚀 Запуск на целевом устройстве:"
echo "   cd $FINAL_DIR"
echo "   ./run_sysrepod.sh        # Запуск sysrepo-демона"
echo "   ./run_klishd.sh          # Запуск klish-демона"
echo "   ./run_klish.sh           # Запуск клиента"
echo ""
echo "📦 Установка YANG-моделей (после запуска sysrepod):"
echo "   sudo ./install_yang_models.sh"
echo ""
echo "🔧 Кросс-компиляция для другой архитектуры:"
echo "   export TARGET_ARCH=arm-linux-gnueabihf"
echo "   ./build_all.sh"