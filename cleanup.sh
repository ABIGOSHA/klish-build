#!/bin/bash
# cleanup.sh - Удаление klish и связанных файлов

echo "=== Очистка системы от klish ==="

# 1. Остановка и отключение сервиса
if systemctl is-active --quiet klishd 2>/dev/null; then
    echo "Остановка klishd..."
    sudo systemctl stop klishd
fi

if [ -f /etc/systemd/system/klishd.service ]; then
    echo "Отключение и удаление systemd unit..."
    sudo systemctl disable klishd 2>/dev/null || true
    sudo rm -f /etc/systemd/system/klishd.service
    sudo systemctl daemon-reload
fi

# 2. Удаление бинарных файлов
echo "Удаление исполняемых файлов..."
sudo rm -f /usr/local/bin/klish
sudo rm -f /usr/local/bin/klishd

# 3. Удаление библиотек (из /usr/lib и /usr/local/lib)
echo "Удаление библиотек..."
sudo rm -f /usr/lib/libklish*
sudo rm -f /usr/lib/libfaux*
sudo rm -f /usr/lib/libtinyrl*
sudo rm -f /usr/local/lib/libklish*
sudo rm -f /usr/local/lib/libfaux*
sudo rm -f /usr/local/lib/libtinyrl*

# Примечание: libxml2 не удаляем, так как может использоваться другими программами
# Если нужно удалить именно собранную libxml2 (из build_root), раскомментируйте:
# sudo rm -f /usr/lib/libxml2.so* 
# sudo rm -f /usr/local/lib/libxml2.so*

# 4. Удаление сокета (если остался)
echo "Удаление сокета..."
sudo rm -f /tmp/klishd.sock
sudo rm -f /tmp/klish-unix-socket

# 5. Удаление конфигурации
echo "Удаление конфигурационных файлов..."
sudo rm -rf /etc/klish

# 6. Обновление кэша библиотек
echo "Обновление кэша библиотек..."
sudo ldconfig

# 7. Удаление временных файлов истории (опционально)
echo "Удаление файлов истории..."
rm -f /tmp/klish_history 2>/dev/null || true

# 8. Проверка
echo ""
echo "=== Проверка ==="
if command -v klish &> /dev/null; then
    echo "❌ klish всё ещё найден: $(which klish)"
else
    echo "✅ klish удалён"
fi

if command -v klishd &> /dev/null; then
    echo "❌ klishd всё ещё найден: $(which klishd)"
else
    echo "✅ klishd удалён"
fi

if [ -d "/etc/klish" ]; then
    echo "❌ /etc/klish всё ещё существует"
else
    echo "✅ /etc/klish удалён"
fi

if [ -e "/tmp/klishd.sock" ]; then
    echo "❌ Сокет /tmp/klishd.sock всё ещё существует"
else
    echo "✅ Сокет удалён"
fi

echo ""
echo "=== Очистка завершена ==="