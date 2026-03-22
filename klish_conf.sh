#!/bin/bash
# klish_conf.sh - Копирование конфигурационных файлов для klish и klishd

set -e

# Находим последнюю собранную папку klish
KLISH_DIR=$(find . -maxdepth 1 -type d -name "klish-build-*" | sort | tail -1)

if [ -z "$KLISH_DIR" ]; then
    echo "Ошибка: Не найдена папка klish-build-*"
    echo "Сначала запустите ./build.sh"
    exit 1
fi

echo "Найдена папка: $KLISH_DIR"

# Проверяем существование источника конфигурации
if [ ! -d "config" ]; then
    echo "Ошибка: Папка 'config' не найдена в текущем каталоге"
    echo "Убедитесь, что ваши конфигурационные файлы лежат в ./config/"
    exit 1
fi

# Создаём папку etc/klish в итоговом пакете
mkdir -p "$KLISH_DIR/etc/klish"

# Копируем конфигурацию
echo "Копирование конфигурации из ./config/ в $KLISH_DIR/etc/klish/"
cp -rv config/* "$KLISH_DIR/etc/klish/"

echo "=== Конфигурация скопирована ==="
echo "Проверьте содержимое: ls -la $KLISH_DIR/etc/klish/"