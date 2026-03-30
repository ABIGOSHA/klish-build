#!/bin/bash
# cleanup.sh - Полная очистка системы от klish и всех связанных компонентов
# Запускать с правами root

set -e

# Проверка прав root
if [ "$EUID" -ne 0 ]; then
    echo "Пожалуйста, запустите с sudo: sudo ./cleanup.sh"
    exit 1
fi

echo "=== ПОЛНАЯ ОЧИСТКА СИСТЕМЫ ОТ KLISH ==="
echo ""
echo "ВНИМАНИЕ! Этот скрипт удалит:"
echo "  - klish и klishd"
echo "  - Библиотеки klish, faux, tinyrl"
echo "  - YANG-модели и sysrepo (опционально)"
echo "  - FreeRADIUS (опционально)"
echo "  - Конфигурационные файлы"
echo "  - Сокеты и временные файлы"
echo ""
read -p "Продолжить? (y/N): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Очистка отменена."
    exit 0
fi

# --- 1. Остановка и отключение сервисов ---
echo ""
echo "=== 1. Остановка сервисов ==="

# Остановка klishd
if systemctl is-active --quiet klishd 2>/dev/null; then
    echo "Остановка klishd..."
    systemctl stop klishd
fi

# Остановка sysrepod
if systemctl is-active --quiet sysrepo 2>/dev/null; then
    echo "Остановка sysrepo..."
    systemctl stop sysrepo
fi

# Остановка freeradius
if systemctl is-active --quiet freeradius 2>/dev/null; then
    echo "Остановка freeradius..."
    systemctl stop freeradius
fi

# --- 2. Удаление systemd units ---
echo ""
echo "=== 2. Удаление systemd units ==="

for unit in klishd sysrepo freeradius; do
    if [ -f "/etc/systemd/system/${unit}.service" ]; then
        echo "Удаление ${unit}.service..."
        systemctl disable "${unit}.service" 2>/dev/null || true
        rm -f "/etc/systemd/system/${unit}.service"
    fi
done
systemctl daemon-reload

# --- 3. Удаление бинарных файлов ---
echo ""
echo "=== 3. Удаление исполняемых файлов ==="

# klish
for bin in klish klishd; do
    for path in /usr/local/bin /usr/bin; do
        if [ -f "$path/$bin" ]; then
            echo "Удаление $path/$bin..."
            rm -f "$path/$bin"
        fi
    done
done

# sysrepo
for bin in sysrepod sysrepoctl sysrepocfg; do
    for path in /usr/local/bin /usr/bin /usr/local/sbin /usr/sbin; do
        if [ -f "$path/$bin" ]; then
            echo "Удаление $path/$bin..."
            rm -f "$path/$bin"
        fi
    done
done

# FreeRADIUS (только если установлен через наш скрипт)
if command -v radtest &> /dev/null; then
    echo ""
    echo "⚠️  FreeRADIUS обнаружен в системе."
    read -p "Удалить FreeRADIUS? (y/N): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Удаление FreeRADIUS..."
        apt remove -y freeradius freeradius-mysql freeradius-utils 2>/dev/null || true
    fi
fi

# --- 4. Удаление библиотек ---
echo ""
echo "=== 4. Удаление библиотек ==="

# Библиотеки klish и связанные
for lib in libklish libfaux libtinyrl; do
    for dir in /usr/lib /usr/local/lib; do
        if [ -d "$dir" ]; then
            rm -f "$dir/${lib}.so"* 2>/dev/null || true
            rm -f "$dir/${lib}.a" 2>/dev/null || true
            rm -f "$dir/${lib}.la" 2>/dev/null || true
        fi
    done
done

# libyang (если устанавливали)
read -p "Удалить libyang? (y/N): " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    for dir in /usr/lib /usr/local/lib; do
        rm -f "$dir/libyang.so"* 2>/dev/null || true
        rm -f "$dir/libyang.a" 2>/dev/null || true
    done
    rm -rf /usr/local/include/libyang 2>/dev/null || true
    echo "✅ libyang удалён"
fi

# sysrepo (если устанавливали)
read -p "Удалить sysrepo? (y/N): " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    for dir in /usr/lib /usr/local/lib; do
        rm -f "$dir/libsysrepo.so"* 2>/dev/null || true
        rm -f "$dir/libsysrepo.a" 2>/dev/null || true
    done
    rm -rf /usr/local/include/sysrepo 2>/dev/null || true
    echo "✅ sysrepo удалён"
fi

# libxml2 (только если она была собрана нами, а не системная)
read -p "Удалить самособранную libxml2? (осторожно! может сломать другие программы) (y/N): " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    for dir in /usr/lib /usr/local/lib; do
        rm -f "$dir/libxml2.so"* 2>/dev/null || true
        rm -f "$dir/libxml2.a" 2>/dev/null || true
    done
    echo "✅ libxml2 удалён"
    echo "ВНИМАНИЕ: Если libxml2 была системной, восстановите её: sudo apt install --reinstall libxml2"
fi

# --- 5. Удаление YANG-моделей и данных sysrepo ---
echo ""
echo "=== 5. Удаление YANG-моделей и данных sysrepo ==="

# Удаление моделей из sysrepo (если установлен)
if command -v sysrepoctl &> /dev/null; then
    echo "Удаление YANG-моделей из sysrepo..."
    for yang in $(sysrepoctl -l 2>/dev/null | grep -v "^ " | tail -n +3 | awk '{print $1}'); do
        sysrepoctl -u -g "$yang" 2>/dev/null || true
    done
fi

# Удаление файлов моделей
for dir in /usr/local/share/yang /usr/share/yang; do
    if [ -d "$dir" ]; then
        echo "Удаление YANG-моделей из $dir..."
        rm -rf "$dir/modules" 2>/dev/null || true
    fi
done

# Удаление данных sysrepo
rm -rf /var/lib/sysrepo 2>/dev/null || true
rm -rf /run/sysrepo 2>/dev/null || true

# --- 6. Удаление конфигурационных файлов ---
echo ""
echo "=== 6. Удаление конфигурационных файлов ==="

# Конфигурация klish
if [ -d "/etc/klish" ]; then
    echo "Удаление /etc/klish..."
    rm -rf /etc/klish
fi

# Конфигурация FreeRADIUS (если устанавливали)
if [ -d "/etc/freeradius" ]; then
    read -p "Удалить конфигурацию FreeRADIUS? (y/N): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf /etc/freeradius
        echo "✅ Конфигурация FreeRADIUS удалена"
    fi
fi

# --- 7. Удаление сокетов и временных файлов ---
echo ""
echo "=== 7. Удаление сокетов и временных файлов ==="

# Сокеты
for sock in /tmp/klishd.sock /tmp/klish-unix-socket /run/klishd.sock; do
    if [ -e "$sock" ]; then
        echo "Удаление $sock..."
        rm -f "$sock"
    fi
done

# Временные файлы
for tmp in /tmp/klish_history /tmp/klish*.tmp; do
    rm -f "$tmp" 2>/dev/null || true
done

# --- 8. Очистка логов (опционально) ---
echo ""
read -p "Очистить журналы systemd для klish? (y/N): " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    journalctl --rotate 2>/dev/null || true
    journalctl --vacuum-time=1s 2>/dev/null || true
    echo "✅ Журналы очищены"
fi

# --- 9. Обновление кэша библиотек ---
echo ""
echo "=== 8. Обновление кэша библиотек ==="
ldconfig

# --- 10. Проверка результатов ---
echo ""
echo "=== 9. ПРОВЕРКА ОЧИСТКИ ==="

# Проверка бинарных файлов
echo ""
echo "Бинарные файлы:"
for bin in klish klishd sysrepod sysrepoctl radtest; do
    if command -v $bin &> /dev/null; then
        echo "  ❌ $bin всё ещё найден: $(which $bin)"
    else
        echo "  ✅ $bin удалён"
    fi
done

# Проверка библиотек
echo ""
echo "Библиотеки:"
for lib in libklish libfaux libtinyrl libyang libsysrepo; do
    if ldconfig -p 2>/dev/null | grep -q "$lib"; then
        echo "  ❌ $lib всё ещё в кэше"
    else
        echo "  ✅ $lib удалён"
    fi
done

# Проверка конфигурации
echo ""
echo "Конфигурационные файлы:"
if [ -d "/etc/klish" ]; then
    echo "  ❌ /etc/klish всё ещё существует"
else
    echo "  ✅ /etc/klish удалён"
fi

# Проверка сокетов
echo ""
echo "Сокеты:"
if [ -e "/tmp/klishd.sock" ] || [ -e "/run/klishd.sock" ]; then
    echo "  ❌ Сокет klishd всё ещё существует"
else
    echo "  ✅ Сокеты удалены"
fi

# --- 11. Финал ---
echo ""
echo "=== ПОЛНАЯ ОЧИСТКА ЗАВЕРШЕНА ==="
echo ""
echo "Если вы устанавливали зависимости через apt, они остались в системе."
echo "Для удаления неиспользуемых пакетов выполните:"
echo "  sudo apt autoremove"
echo ""
echo "Если вы собирали библиотеки из исходников, удалите папки:"
echo "  rm -rf ~/klish-build/src"
echo "  rm -rf ~/klish-build/build_root"