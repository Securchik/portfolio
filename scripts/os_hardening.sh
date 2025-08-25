#!/bin/bash

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Логирование в файл
LOG_FILE="os_hardening_audit_$(date +%Y%m%d).log"
exec > >(tee -a "$LOG_FILE") 2>&1

# Функция проверки результата
check_result() {
  local check_name="$1"
  local status="$2"
  local message="$3"

  case "$status" in
    "PASS")
      echo -e "${GREEN}[PASS]${NC} $check_name: $message"
      ;;
    "WARN")
      echo -e "${YELLOW}[WARN]${NC} $check_name: $message"
      ;;
    "FAIL")
      echo -e "${RED}[FAIL]${NC} $check_name: $message"
      ;;
  esac
}

# Заголовок отчета
echo -e "\n=== Аудит безопасности Linux (18 пунктов) ===\n"
echo "Дата проверки: $(date)"
echo "Хост: $(hostname)"

# 1. Проверка отключения debug-shell
check_debug_shell() {
  if systemctl is-enabled debug-shell.service | grep -q "disabled"; then
    check_result "1. Debug-shell" "PASS" "Служба debug-shell отключена"
  else
    check_result "1. Debug-shell" "FAIL" "Служба debug-shell включена"
  fi
}

# 2. Проверка Avahi Server
check_avahi() {
  if ! dpkg -l | grep -q avahi-daemon; then
    check_result "2. Avahi Server" "PASS" "Avahi не установлен"
  elif systemctl is-active avahi-daemon.service | grep -q "inactive"; then
    check_result "2. Avahi Server" "PASS" "Avahi установлен, но не запущен"
  else
    check_result "2. Avahi Server" "FAIL" "Avahi запущен и работает"
  fi
}

# 3. Проверка Ctrl-Alt-Del
check_ctrl_alt_del() {
  if [ -L /etc/systemd/system/ctrl-alt-del.target ] && \
     [ "$(readlink -f /etc/systemd/system/ctrl-alt-del.target)" = "/dev/null" ]; then
    check_result "3. Ctrl-Alt-Del" "PASS" "Перезагрузка по Ctrl-Alt-Del отключена"
  else
    check_result "3. Ctrl-Alt-Del" "FAIL" "Перезагрузка по Ctrl-Alt-Del включена"
  fi
}

# 4. Проверка Ctrl-Alt-Del Burst Action
check_ctrl_alt_del_burst() {
  if grep -q "^CtrlAltDelBurstAction=none" /etc/systemd/system.conf; then
    check_result "4. Ctrl-Alt-Del Burst" "PASS" "Burst Action отключен"
  else
    check_result "4. Ctrl-Alt-Del Burst" "FAIL" "Burst Action не настроен"
  fi
}

# 5. Проверка создания домашних каталогов
check_home_dirs() {
  if grep -q "^CREATE_HOME\s*yes" /etc/login.defs; then
    check_result "5. Home Directories" "PASS" "CREATE_HOME включен"
  else
    check_result "5. Home Directories" "FAIL" "CREATE_HOME отключен"
  fi
}

# 6. Проверка алгоритма хеширования
check_hash_algorithm() {
  if grep -q "^ENCRYPT_METHOD\s*SHA512" /etc/login.defs; then
    check_result "6. Hash Algorithm" "PASS" "Используется SHA512"
  else
    check_result "6. Hash Algorithm" "FAIL" "SHA512 не настроен"
  fi
}

# 7. Проверка уникальности имен пользователей
check_unique_users() {
  local duplicates=$(getent passwd | awk -F: '{print $1}' | uniq -d)
  if [ -z "$duplicates" ]; then
    check_result "7. Unique Users" "PASS" "Дубликатов не найдено"
  else
    check_result "7. Unique Users" "FAIL" "Найдены дубликаты: $duplicates"
  fi
}

# 8. Проверка истечения срока учетных записей
check_account_expiration() {
  if grep -q "^INACTIVE=35" /etc/default/useradd; then
    check_result "8. Account Expiration" "PASS" "INACTIVE=35 настроен"
  else
    check_result "8. Account Expiration" "FAIL" "INACTIVE не равен 35"
  fi
}

# 9. Проверка пустых паролей
check_empty_passwords() {
  if grep -q "nullok" /etc/pam.d/system-auth; then
    check_result "9. Empty Passwords" "FAIL" "Пустые пароли разрешены"
  else
    check_result "9. Empty Passwords" "PASS" "Пустые пароли запрещены"
  fi
}

# 10. Проверка shadow-паролей
check_shadow_passwords() {
  if awk -F: '$2 != "x" {print $1}' /etc/passwd | grep -q .; then
    check_result "10. Shadow Passwords" "FAIL" "Найдены пароли в /etc/passwd"
  else
    check_result "10. Shadow Passwords" "PASS" "Все пароли в /etc/shadow"
  fi
}

# 11. Проверка минимальной длины пароля
check_min_password_length() {
  if grep -q "^PASS_MIN_LEN\s*16" /etc/login.defs; then
    check_result "11. Min Password Length" "PASS" "Минимальная длина: 16"
  else
    check_result "11. Min Password Length" "FAIL" "Длина меньше 16 символов"
  fi
}

# 12. Проверка MOTD
check_motd() {
  if [ -f /etc/motd ]; then
    check_result "12. MOTD" "PASS" "Файл /etc/motd существует"
  else
    check_result "12. MOTD" "WARN" "Файл /etc/motd отсутствует"
  fi
}

# 13. Проверка прав GRUB
check_grub_permissions() {
  if [ -f /boot/grub2/grub.cfg ]; then
    local perms=$(stat -c "%a" /boot/grub2/grub.cfg)
    local owner=$(stat -c "%U:%G" /boot/grub2/grub.cfg)
    if [ "$perms" = "600" ] && [ "$owner" = "root:root" ]; then
      check_result "13. GRUB Permissions" "PASS" "Правильные права (600) и владелец (root:root)"
    else
      check_result "13. GRUB Permissions" "FAIL" "Неправильные права ($perms) или владелец ($owner)"
    fi
  else
    check_result "13. GRUB Permissions" "WARN" "Файл /boot/grub2/grub.cfg не найден"
  fi
}

# 14. Проверка профилирования ядра
check_kernel_profiling() {
  if grep -q "^kernel.perf_event_paranoid\s*=\s*2" /etc/sysctl.conf || \
     [ "$(sysctl -n kernel.perf_event_paranoid)" -eq 2 ]; then
    check_result "14. Kernel Profiling" "PASS" "Профилирование ограничено (paranoid=2)"
  else
    check_result "14. Kernel Profiling" "FAIL" "Профилирование не ограничено"
  fi
}

# 15. Проверка vsyscall
check_vsyscall() {
  if grep -q "vsyscall=none" /etc/default/grub; then
    check_result "15. Vsycalls" "PASS" "Vsyscall отключен"
  else
    check_result "15. Vsycalls" "FAIL" "Vsyscall включен"
  fi
}

# 16. Проверка kexec_load
check_kexec_load() {
  if grep -q "^kernel.kexec_load_disabled\s*=\s*1" /etc/sysctl.conf || \
     [ "$(sysctl -n kernel.kexec_load_disabled)" -eq 1 ]; then
    check_result "16. Kexec Load" "PASS" "Kexec_load отключен"
  else
    check_result "16. Kexec Load" "FAIL" "Kexec_load включен"
  fi
}

# 17. Проверка BPF JIT
check_bpf_jit() {
  if grep -q "^net.core.bpf_jit_harden\s*=\s*2" /etc/sysctl.conf || \
     [ "$(sysctl -n net.core.bpf_jit_harden)" -eq 2 ]; then
    check_result "17. BPF JIT" "PASS" "BPF JIT усилен (уровень 2)"
  else
    check_result "17. BPF JIT" "FAIL" "BPF JIT не усилен"
  fi
}

# 18. Проверка dmesg
check_dmesg_restrict() {
  if grep -q "^kernel.dmesg_restrict\s*=\s*1" /etc/sysctl.conf || \
     [ "$(sysctl -n kernel.dmesg_restrict)" -eq 1 ]; then
    check_result "18. Dmesg Restrict" "PASS" "Dmesg ограничен"
  else
    check_result "18. Dmesg Restrict" "FAIL" "Dmesg не ограничен"
  fi
}

# Запуск всех проверок
check_debug_shell
check_avahi
check_ctrl_alt_del
check_ctrl_alt_del_burst
check_home_dirs
check_hash_algorithm
check_unique_users
check_account_expiration
check_empty_passwords
check_shadow_passwords
check_min_password_length
check_motd
check_grub_permissions
check_kernel_profiling
check_vsyscall
check_kexec_load
check_bpf_jit
check_dmesg_restrict

echo -e "\n=== Аудит завершен ==="
echo "Результаты сохранены в $LOG_FILE"
