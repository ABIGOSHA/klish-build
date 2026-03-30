#!/bin/bash
# build.sh - Компиляция klish с поддержкой libyang и sysrepo

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

# --- СОЗДАНИЕ КОНФИГУРАЦИОННЫХ ФАЙЛОВ ДЛЯ KLISH ---
echo "=== Проверка наличия конфигурационных файлов ==="

# klish.conf (создаётся, если отсутствует)
if [ ! -f "$(pwd)/config/klish.conf" ]; then
    echo "Создание klish.conf (по умолчанию)..."
    cat > "$(pwd)/config/klish.conf" << 'EOF'
UnixSocketPath=/tmp/klishd.sock
Pager="/usr/bin/less -I -F -e -X -K -d -R"
UsePager=y
HistorySize=100
Completion=true
HistoryFile=/tmp/klish_history
EOF
else
    echo "✅ klish.conf уже существует, используется существующий"
fi

# klishd.conf (создаётся, если отсутствует)
if [ ! -f "$(pwd)/config/klishd.conf" ]; then
    echo "Создание klishd.conf (по умолчанию)..."
    cat > "$(pwd)/config/klishd.conf" << 'EOF'
UnixSocketPath=/tmp/klishd.sock
UnixSocketMode=0666

# Базы данных
DBs=libxml2
DB.libxml2.XMLPath=/etc/klish/simple.xml

# Путь к плагинам
PluginPath=/usr/local/lib

# Поддержка sysrepo (YANG)
DBs += sysrepo
DB.sysrepo.YANGPath=/usr/local/share/yang/modules
EOF
else
    echo "✅ klishd.conf уже существует, используется существующий"
fi

# simple.xml (ПРОВЕРКА: если нет в config, выдаём предупреждение)
if [ ! -f "$(pwd)/config/simple.xml" ]; then
    echo "⚠️  ВНИМАНИЕ: simple.xml не найден в папке config/"
    echo "   Создаю минимальный файл для тестирования."
    cat > "$(pwd)/config/simple.xml" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<klish>
    <view name="root">
        <command name="hello" help="Say hello">
            <action>echo "Hello from klish!"</action>
        </command>
        <command name="exit" help="Exit">
            <action>exit 0</action>
        </command>
    </view>
</klish>
EOF
else
    echo "✅ simple.xml найден, используется существующий"
    echo "   Размер файла: $(wc -l < "$(pwd)/config/simple.xml") строк"
fi

# Проверка наличия YANG-моделей в config (опционально)
if [ -d "$(pwd)/config/yang" ]; then
    echo "✅ Найдены пользовательские YANG-модели в config/yang/"
    ls -la "$(pwd)/config/yang/"*.yang 2>/dev/null || echo "   (нет .yang файлов)"
fi

echo "✅ Конфигурационные файлы готовы"

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
export CFLAGS="-I$PREFIX/include -I$PREFIX/include/libyang -I$PREFIX/include/sysrepo"
export LDFLAGS="-L$PREFIX/lib"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:$PKG_CONFIG_PATH"
export PATH="$PREFIX/bin:$PATH"

# --- СБОРКА LIBYANG И SYSREPO (ЕСЛИ НЕ СОБРАНЫ) ---
echo ""
echo "=== Проверка и сборка libyang и sysrepo ==="

# Сборка libyang, если не собрана
if [ ! -f "$PREFIX/lib/libyang.so" ] && [ ! -f "$PREFIX/lib/libyang.a" ]; then
    echo "Сборка libyang..."
    cd "$(pwd)/src/libyang"
    if [ ! -d "build" ]; then
        mkdir build
    fi
    cd build
    cmake -DCMAKE_INSTALL_PREFIX="$PREFIX" \
          -DCMAKE_C_COMPILER="${CC:-gcc}" \
          -DCMAKE_CXX_COMPILER="${CXX:-g++}" \
          -DCMAKE_C_FLAGS="$CFLAGS" \
          -DCMAKE_CXX_FLAGS="$CFLAGS" \
          -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS" \
          -DCMAKE_SHARED_LINKER_FLAGS="$LDFLAGS" \
          -DCMAKE_MODULE_LINKER_FLAGS="$LDFLAGS" \
          -DENABLE_BUILD_TESTS=OFF \
          -DENABLE_BUILD_TOOLS=ON ..
    make -j$(nproc)
    make install
    cd ../..
    echo "✅ libyang собрана"
else
    echo "✅ libyang уже собрана"
fi

# Сборка sysrepo, если не собрана
if [ ! -f "$PREFIX/lib/libsysrepo.so" ] && [ ! -f "$PREFIX/lib/libsysrepo.a" ]; then
    echo "Сборка sysrepo..."
    cd "$(pwd)/src/sysrepo"
    if [ ! -d "build" ]; then
        mkdir build
    fi
    cd build
    cmake -DCMAKE_INSTALL_PREFIX="$PREFIX" \
          -DCMAKE_C_COMPILER="${CC:-gcc}" \
          -DCMAKE_CXX_COMPILER="${CXX:-g++}" \
          -DCMAKE_C_FLAGS="$CFLAGS" \
          -DCMAKE_CXX_FLAGS="$CFLAGS" \
          -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS" \
          -DCMAKE_SHARED_LINKER_FLAGS="$LDFLAGS" \
          -DCMAKE_MODULE_LINKER_FLAGS="$LDFLAGS" \
          -DGEN_LANGUAGE_BINDINGS=ON \
          -DGEN_CPP_BINDINGS=ON \
          -DENABLE_TESTS=OFF \
          -DENABLE_CACHE=ON \
          -DPRINTED_CONTEXT_ADDRESS=1 \
          -DSYSREPO_PRINTED_CONTEXT_ADDRESS=1 ..
    make -j$(nproc)
    make install
    cd ../..
    echo "✅ sysrepo собрана"
else
    echo "✅ sysrepo уже собрана"
fi

# --- Проверка наличия зависимостей ---
echo ""
echo "=== Проверка зависимостей ==="

# Проверка faux
if [ ! -f "$PREFIX/lib/libfaux.so" ] && [ ! -f "$PREFIX/lib/libfaux.a" ]; then
    echo "Ошибка: библиотека faux не найдена в $PREFIX"
    echo "Сначала запустите ./setup.sh"
    exit 1
fi
echo "✅ faux найдена"

# Проверка libxml2
if [ ! -f "$PREFIX/lib/libxml2.so" ] && [ ! -f "$PREFIX/lib/libxml2.a" ]; then
    echo "Ошибка: библиотека libxml2 не найдена в $PREFIX"
    echo "Сначала запустите ./setup.sh"
    exit 1
fi
echo "✅ libxml2 найдена"

# Проверка libyang
if [ ! -f "$PREFIX/lib/libyang.so" ] && [ ! -f "$PREFIX/lib/libyang.a" ]; then
    echo "⚠️  Предупреждение: libyang не найдена (YANG-моделирование может не работать)"
    YANG_AVAILABLE=0
else
    echo "✅ libyang найдена"
    YANG_AVAILABLE=1
fi

# Проверка sysrepo
if [ ! -f "$PREFIX/lib/libsysrepo.so" ] && [ ! -f "$PREFIX/lib/libsysrepo.a" ]; then
    echo "⚠️  Предупреждение: sysrepo не найдена (управление конфигурацией YANG может не работать)"
    SYSREPO_AVAILABLE=0
else
    echo "✅ sysrepo найдена"
    SYSREPO_AVAILABLE=1
fi

# --- Сборка klish ---
echo ""
echo "=== Сборка klish ==="
cd "$(pwd)/src/klish-3.2.0"

CONFIGURE_FLAGS="--prefix=$BUILD_DIR \
            --host=$TARGET_ARCH \
            --with-faux=$PREFIX \
            --with-libxml2=$PREFIX \
            --sysconfdir=$CONFIG_DIR/etc"

if [ $YANG_AVAILABLE -eq 1 ]; then
    CONFIGURE_FLAGS="$CONFIGURE_FLAGS --with-libyang=$PREFIX"
fi

if [ $SYSREPO_AVAILABLE -eq 1 ]; then
    CONFIGURE_FLAGS="$CONFIGURE_FLAGS --with-sysrepo=$PREFIX"
fi

echo "Конфигурация klish..."
./configure $CONFIGURE_FLAGS

echo "Компиляция klish..."
make -j$(nproc)

echo "Установка klish..."
make install

cd - > /dev/null
echo "✅ klish собран"

# --- Сборка klish-plugin-sysrepo (если доступен) ---
if [ $SYSREPO_AVAILABLE -eq 1 ] && [ -d "$(pwd)/src/klish-plugin-sysrepo" ]; then
    echo ""
    echo "=== Сборка klish-plugin-sysrepo ==="
    cd "$(pwd)/src/klish-plugin-sysrepo"
    
    make clean 2>/dev/null || true
    
    ./configure --prefix="$BUILD_DIR" \
                --host="$TARGET_ARCH" \
                --with-sysrepo="$PREFIX" \
                --with-libyang="$PREFIX" \
                --with-klish="$BUILD_DIR"
    
    make -j$(nproc)
    make install
    
    cd - > /dev/null
    echo "✅ klish-plugin-sysrepo собран"
fi

# --- Формирование итогового пакета ---
echo ""
echo "=== Формирование итогового пакета ==="

# Копируем klish
cp -r "$BUILD_DIR"/* "$FINAL_DIR/"

# Копирование конфигурации klish из папки config
if [ -d "$(pwd)/config" ]; then
    echo "Копирование конфигурации klish из папки config/..."
    mkdir -p "$FINAL_DIR/etc/klish"
    cp -rv "$(pwd)/config/"* "$FINAL_DIR/etc/klish/" 2>/dev/null || true
    echo "✅ Конфигурация скопирована"
fi

# --- КОПИРОВАНИЕ БИБЛИОТЕК LIBYANG И SYSREPO В ИТОГОВЫЙ ПАКЕТ ---
echo ""
echo "=== Копирование библиотек libyang и sysrepo ==="

mkdir -p "$FINAL_DIR/lib"

# Копируем libyang
if [ -f "$PREFIX/lib/libyang.so" ]; then
    cp -v "$PREFIX/lib/libyang.so"* "$FINAL_DIR/lib/" 2>/dev/null || true
    echo "✅ libyang скопирована"
fi

# Копируем libsysrepo
if [ -f "$PREFIX/lib/libsysrepo.so" ]; then
    cp -v "$PREFIX/lib/libsysrepo.so"* "$FINAL_DIR/lib/" 2>/dev/null || true
    echo "✅ libsysrepo скопирована"
fi

# Копируем заголовочные файлы
if [ -d "$PREFIX/include/libyang" ]; then
    mkdir -p "$FINAL_DIR/include/libyang"
    cp -rv "$PREFIX/include/libyang"/* "$FINAL_DIR/include/libyang/" 2>/dev/null || true
fi

if [ -d "$PREFIX/include/sysrepo" ]; then
    mkdir -p "$FINAL_DIR/include/sysrepo"
    cp -rv "$PREFIX/include/sysrepo"/* "$FINAL_DIR/include/sysrepo/" 2>/dev/null || true
fi

# --- КОПИРОВАНИЕ YANG-МОДЕЛЕЙ ИЗ BUILD_ROOT ---
echo ""
echo "=== Копирование YANG-моделей из собранных зависимостей ==="

mkdir -p "$FINAL_DIR/share/yang/modules"

# Копируем модели из libyang
if [ -d "$PREFIX/share/yang/modules/libyang" ]; then
    echo "Копирование моделей libyang..."
    cp -rv "$PREFIX/share/yang/modules/libyang/"* "$FINAL_DIR/share/yang/modules/" 2>/dev/null || true
    echo "✅ Модели libyang скопированы"
else
    echo "⚠️  Модели libyang не найдены в $PREFIX/share/yang/modules/libyang"
fi

# Копируем модели из sysrepo
if [ -d "$PREFIX/share/yang/modules/sysrepo" ]; then
    echo "Копирование моделей sysrepo..."
    cp -rv "$PREFIX/share/yang/modules/sysrepo/"* "$FINAL_DIR/share/yang/modules/" 2>/dev/null || true
    echo "✅ Модели sysrepo скопированы"
else
    echo "⚠️  Модели sysrepo не найдены в $PREFIX/share/yang/modules/sysrepo"
fi

# Копируем пользовательские YANG-модели из config/yang (если есть)
if [ -d "$(pwd)/config/yang" ]; then
    echo "Копирование пользовательских YANG-моделей из config/yang/..."
    cp -rv "$(pwd)/config/yang/"* "$FINAL_DIR/share/yang/modules/" 2>/dev/null || true
    echo "✅ Пользовательские модели скопированы"
fi

# Подсчёт скопированных моделей
YANG_COUNT=$(find "$FINAL_DIR/share/yang/modules" -name "*.yang" 2>/dev/null | wc -l)
echo "📊 Всего скопировано YANG-моделей: $YANG_COUNT"

# --- Создание скриптов для запуска ---
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
export SYSREPO_PATH="$SCRIPT_DIR/share/yang/modules"
exec "$SCRIPT_DIR/bin/klish" "$@"
EOF
chmod +x "$FINAL_DIR/run_klish.sh"

# Скрипт для установки YANG-моделей в sysrepo
cat > "$FINAL_DIR/install_yang_models.sh" << 'EOF'
#!/bin/bash
# install_yang_models.sh - Установка YANG-моделей в sysrepo
# Запускать с правами root

if [ "$EUID" -ne 0 ]; then
    echo "Пожалуйста, запустите с sudo: sudo ./install_yang_models.sh"
    exit 1
fi

echo "=== Установка YANG-моделей в sysrepo ==="

# Путь к YANG-моделям
YANG_DIR="$(dirname "$0")/share/yang/modules"

if [ -d "$YANG_DIR" ]; then
    YANG_COUNT=$(find "$YANG_DIR" -name "*.yang" 2>/dev/null | wc -l)
    echo "Найдено YANG-моделей: $YANG_COUNT"
    
    for yang_file in "$YANG_DIR"/*.yang; do
        if [ -f "$yang_file" ]; then
            echo "Установка $(basename "$yang_file")..."
            sysrepoctl -i -g "$yang_file" 2>/dev/null || echo "  Модель уже установлена или ошибка"
        fi
    done
else
    echo "⚠️  YANG-модели не найдены в $YANG_DIR"
fi

echo "=== Установка завершена ==="
echo "Для просмотра установленных моделей: sysrepoctl -l"
EOF
chmod +x "$FINAL_DIR/install_yang_models.sh"

# Скрипт для установки FreeRADIUS
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

if [ -d "$(dirname "$0")/etc/freeradius" ]; then
    echo "Копирование конфигурации FreeRADIUS..."
    cp -rv "$(dirname "$0")/etc/freeradius"/* /etc/freeradius/3.0/
fi

echo "=== FreeRADIUS установлен ==="
echo "Для запуска: sudo systemctl start freeradius"
echo "Для теста: radtest testuser testpass localhost 0 testing123"
EOF
chmod +x "$FINAL_DIR/install_radius.sh"

echo ""
echo "=== Сборка завершена ==="
echo "Итоговый пакет: $FINAL_DIR"
echo ""
echo "📊 Статистика:"
echo "   - Конфигурация: $(ls -1 "$FINAL_DIR/etc/klish" 2>/dev/null | wc -l) файлов"
echo "   - YANG-модели: $(find "$FINAL_DIR/share/yang/modules" -name "*.yang" 2>/dev/null | wc -l) файлов"
echo "   - Библиотеки: $(ls -1 "$FINAL_DIR/lib" 2>/dev/null | wc -l) файлов"
echo ""
echo "Для запуска демона klish:"
echo "  cd $FINAL_DIR && ./run_klishd.sh"
echo ""
echo "Для запуска клиента klish:"
echo "  cd $FINAL_DIR && ./run_klish.sh"
echo ""
echo "Для установки YANG-моделей в sysrepo:"
echo "  cd $FINAL_DIR && sudo ./install_yang_models.sh"
echo ""
echo "Для установки FreeRADIUS на целевом устройстве:"
echo "  cd $FINAL_DIR && sudo ./install_radius.sh"
echo ""
echo "Для установки klish в систему:"
echo "  sudo ./install.sh"