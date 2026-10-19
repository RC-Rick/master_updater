#!/bin/bash
# ---------------------------------------------------------
# Скрипт:       master_updater.sh
# Назначение:   Мастер по автоматическому обновлению Astra Linux 1.8
# Автор:        RC-Rick
# Версия:       0.7
# Дата создания: 2026-07-15
# Обновлено:    2026-10-19
#
# Использование: sudo bash master_updater.sh [-u] [-m] [-a] [-h]
#   -u  - обновить систему (автоматически, по текущему sources.list)
#   -m  - ручное обновление (запрос параметров репозитория)
#   -a  - обновление через astra-update (по текущему sources.list)
#   -h  - эта справка
#
# Важно: 
#   [!] Запускать от root или через sudo!
# ---------------------------------------------------------
# set -euo pipefail

SCRIPT_NAME="${0##*/}"
SCRIPT_VERSION="0.7"
SCRIPT_AUTHOR="RC-Rick"
SCRIPT_DESC="Мастер по автоматическому обновлению Astra Linux 1.8"
SCRIPT_CREATED="2026-05-27"
SCRIPT_UPDATED="2026-10-19"

LOGFILE="/var/log/ASTRAOPS/master_updater/master_updater(Dev).log"
MAIN_LOG="/var/log/ASTRAOPS/master_updater/master_updater(MAIN).log"

OS=`cat /etc/astra/build_version | cut -d '.' -f1,2`
OS_NAME=`uname -s`
OS_VERSION=`cat /etc/*release | grep "DESCRIPTION" | awk -F'"' '{print $2}'`
OS_UPDATE=`cat /etc/astra/build_version`
S_NAME=$(hostname -s)
UPDATE=`cat /etc/astra/build_version | cut -d '.' -f1,2,3`
SOURCES="/etc/apt/sources.list"

# ===== Конфигурация репозитория (значения по умолчанию) =====
# В режиме -m (manual (ручное обновление) вы можете переопределить эти значения.
REPO_PROTO="http"
REPO_HOST=""
REPO_BASE=""
REPO_MAIN_DIR="main-repository"
REPO_EXT_DIR="extended-repository"
REPO_COMP="main contrib non-free non-free-firmware"

LATEST_FULL="1.8.6.39"

VERSIONS_ORDER=("1.8.1.12" "1.8.2.8" "1.8.3.7" "1.8.4.48" "1.8.5.46" "1.8.6.39")

declare -A REPO_MAP=(
    ["1.8.1.12"]="astra_1.8.1"
    ["1.8.2.8"]="astra_1.8_latest"
    ["1.8.3.7"]="astra_1.8.3"
    ["1.8.4.48"]="astra_1.8.4"
    ["1.8.5.46"]="astra_1.8.5"
    ["1.8.6.39"]="astra_1.8.6"
)
# ============================================================

green='\033[0;32m'
red='\033[0;31m'
blue='\033[0;36m'
reset='\033[0m'
orange='\033[0;33m'
pur='\033[0;35m'
toend=$(tput hpa $(tput cols))$(tput cub 10)

ERROR="False"

HELP_LINES=(
    "-u|Обновление системы (автоматически, по текущему sources.list)"
    "-m|Обновление системы (ручное, с запросом параметров репозитория)"
    "-a|Обновление системы (astra-update, по текущему sources.list)"
    "-h, --help|Показать эту справку и выйти"
)

HELP_NOTES=(
    "[!] Запускайте скрипт от root или через sudo."
    "[!] Не прерывайте выполнение — возможна частичная настройка системы."
    "[!] Ключ -a рекомендуется при переходе с 1.8.1 на 1.8.2."
)


log() {
    if [[ $1 == 'start' ]];then
        printf "##################[ START LOG ]##################\n" >> $MAIN_LOG
    elif [[ $1 == 'end' ]];then
        printf "##################[ END   LOG ]##################\n\n" >> $MAIN_LOG
    else
        local time=$(date +%H:%M.%S)
        local description=$1
        local status='[ * ]'
        if [[ $2 != '' ]];then
            if [ $2 -eq 0 ];then
                status='[ УСПЕШНО ]'
            else
                status='[ ОШИБКА ]'
            fi
        fi
        printf "%s\t%s - %s;\n" "$status" "$time" "$description" >> $MAIN_LOG
    fi
}
log_check_dir() {
    PATH_LOG="/var/log/ASTRAOPS/master_updater"
    if [ ! -d $PATH_LOG ];then
        sudo mkdir -p $PATH_LOG
        if [ $? -ne 0 ];then
            echo "ОШИБКА! Не удалось создать директорию $PATH_LOG"
            exit 1
        fi
    fi
}

check_OS() {
    [[ $OS =~ ^1\.[67]$ ]] && echo -e "${red}ОШИБКА! ${blue}Astra Linux 1.6/1.7${red} не поддерживается!${reset}" && exit 1
}

check() {
    if [ $1 -eq 0 ]; then
        echo -ne "${TOEND}${GREEN}[Успешно]${RESET}"
    else
        echo -ne "${TOEND}${RED}[Ошибка]${RESET}"
    fi
    echo ""
}

show_help() {
    echo
    echo "=================================================="
    echo "  $SCRIPT_NAME - $SCRIPT_DESC"
    echo "=================================================="
    echo " Автор:       $SCRIPT_AUTHOR"
    echo " Версия:      $SCRIPT_VERSION"
    echo " Создано:     $SCRIPT_CREATED"
    echo " Обновлено:   $SCRIPT_UPDATED"
    echo
    echo " Использование: $SCRIPT_NAME [КЛЮЧИ]"
    echo
    echo " Доступные ключи:"
    for line in "${HELP_LINES[@]}"; do
        IFS='|' read -r key desc <<< "$line"
        printf "   %-15s %s\n" "$key" "$desc"
    done
    echo
    if [[ ${#HELP_NOTES[@]} -gt 0 ]]; then
        echo " Важно:"
        for note in "${HELP_NOTES[@]}"; do
            echo "   $note"
        done
    fi
    echo
    echo -e "${blue}СИСТЕМА ${pur}= ${green}[ ${orange}$OS_NAME${green} ]${reset}"
    echo -e "${blue}РЕЛИЗ ${pur}= ${green}[ ${orange}$OS_UPDATE${green} ]${reset}"
    echo -e "${blue}ИМЯ ${pur}= ${green}[ ${orange}$S_NAME${green} ]${reset}"
    echo -e "${blue}ВЕРСИЯ ОС ${pur}= ${green}[ ${orange}$OS_VERSION${green} ]${reset}"
    echo "=================================================="
    echo
}

title_menu() {
    title=$1
    echo -e "${orange}╔════════════════════[ ${red}AstraOps${orange} ]════════════════════╗"
    echo -e "║ ${green}Вас приветствует ${blue}master_updater ${red}v${pur}$SCRIPT_VERSION            ${orange}║"
    echo -e "║ ${green}Автор скрипта ${blue}[ ${red}RC-Rick ${blue}]                     ${orange}║"
    if [[ "$title" == "auto" ]];then
        echo -e "║ ${green}Выбран режим: ${orange}$title                              ${orange}║"
    elif [[ "$title" == "manual" ]];then
        echo -e "║ ${green}Выбран режим: ${orange}$title                            ${orange}║"
    else
        echo -e "║ ${green}Выбран режим: ${orange}$title                             ${orange}║"
    fi
    echo -e "${orange}╚═════════════════════════════════════════════════╝${reset}"
}

check_sources_versions() {
    local versions count
    versions=$(grep -oE 'astra_1\.8[._][0-9a-zA-Z]+' "$SOURCES" 2>/dev/null | sort -u)
    count=$(echo "$versions" | grep -c . || true)
    if [ "$count" -gt 1 ]; then
        echo -e "${red}В $SOURCES найдено несколько версий репозитория:${reset}"
        echo "$versions"
        echo -e "${red}Оставьте только одну версию и повторите запуск.${reset}"
        return 1
    fi
    return 0
}

safe_apt_update() {
    rm -f /tmp/update.log
    apt-get update -qq 2>&1 | tee -a "/tmp/update.log"
    
    if grep -q "^W:" /tmp/update.log; then
        echo -e "${red}Обнаружены предупреждения apt. Проверьте ${orange}$SOURCES${reset}"
        grep "^W:" /tmp/update.log
    fi
    return 0
}

prompt_repo_config() {
    echo -e "${blue}Введите параметры репозитория (Enter - оставить значение по умолчанию):${reset}"
    local input

    read -rp "Протокол [${REPO_PROTO}]: " input
    REPO_PROTO="${input:-$REPO_PROTO}"

    read -rp "IP или хост репозитория: " input
    REPO_HOST="${input:-$REPO_HOST}"

    read -rp "Базовый путь до каталогов версий (например /repo): " input
    REPO_BASE="${input:-$REPO_BASE}"

    read -rp "Имя каталога main [${REPO_MAIN_DIR}]: " input
    REPO_MAIN_DIR="${input:-$REPO_MAIN_DIR}"

    read -rp "Имя каталога extended [${REPO_EXT_DIR}]: " input
    REPO_EXT_DIR="${input:-$REPO_EXT_DIR}"

    read -rp "Компоненты [${REPO_COMP}]: " input
    REPO_COMP="${input:-$REPO_COMP}"

    if [ -z "$REPO_HOST" ] || [ -z "$REPO_BASE" ]; then
        echo -e "${red}Хост и базовый путь обязательны!${reset}"
        return 1
    fi
    return 0
}

generate_sources_for_version() {
    local repo_dir="$1"
    if [ -z "$repo_dir" ]; then
        echo -e "${red}Не передано имя каталога репозитория!${reset}"
        return 1
    fi

    local base_url="${REPO_PROTO}://${REPO_HOST}${REPO_BASE}/${repo_dir}"

    cat > "$SOURCES" <<EOF
deb [arch=amd64] ${base_url}/${REPO_MAIN_DIR}/ 1.8_x86-64 ${REPO_COMP}
deb [arch=amd64] ${base_url}/${REPO_EXT_DIR}/ 1.8_x86-64 ${REPO_COMP}
EOF

    echo -e "${pur}[ ${red}* ${pur}] ${green}Сформирован ${orange}$SOURCES${green}:${reset}"
    cat "$SOURCES"
    return 0
}

run_dist_upgrade_with_progress() {
    STATUS=$1
    CURRENT=0
    DOWNLOAD_DONE=false
    POST_INSTALL=false
    
    printf "Загрузка пакетов..."
    while true; do
        for symbol in '⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏'; do
            [[ "$DOWNLOAD_DONE" == true ]] && break 2
            printf "\rЗагрузка пакетов... %s" "$symbol"
            sleep 0.1
        done
    done &
    SPINNER_PID=$!
    trap "kill $SPINNER_PID 2>/dev/null; wait $SPINNER_PID 2>/dev/null" RETURN
    
    if [[ "$STATUS" == "astra" ]];then
        LC_ALL=C stdbuf -oL astra-update -r -T -A 2>&1 | \
        LC_ALL=C stdbuf -oL tee -a "/tmp/log_update.log" | \
        while IFS= read -r line; do
            if [[ "$line" =~ ^(Unpacking|Setting\ up|Processing\ triggers) ]]; then
                
                if [[ "$DOWNLOAD_DONE" == false ]]; then
                    DOWNLOAD_DONE=true
                    kill $SPINNER_PID 2>/dev/null
                    wait $SPINNER_PID 2>/dev/null
                    printf "\r\033[K"
                fi
                
                ((CURRENT++)) || true
                
                if [ "$TOTAL_PKGS" -gt 0 ]; then
                    PKG_NAME=$(echo "$line" | awk '{print $3}')
                    PKG_NAME="${PKG_NAME:0:18}"
                    
                    if [ "$CURRENT" -le "$TOTAL_PKGS" ]; then
                        PCT=$(( CURRENT * 100 / TOTAL_PKGS ))
                        FILLED=$(( PCT / 2 ))
                        EMPTY=$(( 50 - FILLED ))
                        BAR=$(printf '%*s' "$FILLED" '' | tr ' ' '#')
                        SPACES=$(printf '%*s' "$EMPTY" '' | tr ' ' '-')
                        
                        printf "\r\033[K[%s%s] %3d%% (%d/%d) %-18s" \
                            "$BAR" "$SPACES" "$PCT" "$CURRENT" "$TOTAL_PKGS" "$PKG_NAME"
                    else
                        POST_INSTALL=true
                        EXTRA=$(( CURRENT - TOTAL_PKGS ))
                        
                        POST_LEN=$(( EXTRA > 10 ? 10 : EXTRA ))
                        POST_BAR=$(printf '%*s' "$POST_LEN" '' | tr ' ' '+')
                        REMAINING=$(( 10 - POST_LEN ))
                        POST_EMPTY=$(printf '%*s' "$REMAINING" '' | tr ' ' ' ')
                        
                        ANIM_SYMBOLS=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴')
                        ANIM_IDX=$(( EXTRA % ${#ANIM_SYMBOLS[@]} ))
                        ANIM="${ANIM_SYMBOLS[$ANIM_IDX]}"
                        
                        printf "\r\033[K[##################################################%s%s] POST (%d) %s %-18s" \
                            "$POST_BAR" "$POST_EMPTY" "$EXTRA" "$ANIM" "$PKG_NAME"
                    fi
                fi
            fi
        done
    else
        LC_ALL=C stdbuf -oL apt-get \
            -o Dpkg::Options::="--force-confdef" \
            dist-upgrade -y 2>&1 | \
        LC_ALL=C stdbuf -oL tee -a "/tmp/log_update.log" | \
        while IFS= read -r line; do
            if [[ "$line" =~ ^(Unpacking|Setting\ up|Processing\ triggers) ]]; then
                
                if [[ "$DOWNLOAD_DONE" == false ]]; then
                    DOWNLOAD_DONE=true
                    kill $SPINNER_PID 2>/dev/null
                    wait $SPINNER_PID 2>/dev/null
                    printf "\r\033[K"
                fi
                
                ((CURRENT++)) || true
                
                if [ "$TOTAL_PKGS" -gt 0 ]; then
                    PKG_NAME=$(echo "$line" | awk '{print $3}')
                    PKG_NAME="${PKG_NAME:0:18}"
                    
                    if [ "$CURRENT" -le "$TOTAL_PKGS" ]; then
                        PCT=$(( CURRENT * 100 / TOTAL_PKGS ))
                        FILLED=$(( PCT / 2 ))
                        EMPTY=$(( 50 - FILLED ))
                        BAR=$(printf '%*s' "$FILLED" '' | tr ' ' '#')
                        SPACES=$(printf '%*s' "$EMPTY" '' | tr ' ' '-')
                        
                        printf "\r\033[K[%s%s] %3d%% (%d/%d) %-18s" \
                            "$BAR" "$SPACES" "$PCT" "$CURRENT" "$TOTAL_PKGS" "$PKG_NAME"
                    else
                        POST_INSTALL=true
                        EXTRA=$(( CURRENT - TOTAL_PKGS ))
                        
                        POST_LEN=$(( EXTRA > 10 ? 10 : EXTRA ))
                        POST_BAR=$(printf '%*s' "$POST_LEN" '' | tr ' ' '+')
                        REMAINING=$(( 10 - POST_LEN ))
                        POST_EMPTY=$(printf '%*s' "$REMAINING" '' | tr ' ' ' ')
                        
                        ANIM_SYMBOLS=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴')
                        ANIM_IDX=$(( EXTRA % ${#ANIM_SYMBOLS[@]} ))
                        ANIM="${ANIM_SYMBOLS[$ANIM_IDX]}"
                        
                        printf "\r\033[K[##################################################%s%s] POST (%d) %s %-18s" \
                            "$POST_BAR" "$POST_EMPTY" "$EXTRA" "$ANIM" "$PKG_NAME"
                    fi
                fi
            fi
        done
    fi
    
    echo ""
    EXIT_CODE=${PIPESTATUS[0]}
    
    if [ "$EXIT_CODE" -eq 0 ]; then
        NEW_VERSION=$(cat /etc/astra/build_version 2>/dev/null | tr -d '[:space:]')
        echo ""
        echo -e "${pur}╔══════════════════════════════════════════════════╗${reset}"
        echo -e "${pur}║       ${green}  ОБНОВЛЕНИЕ УСПЕШНО ЗАВЕРШЕНО${reset}             ${pur}║${reset}"
        echo -e "${pur}╠══════════════════════════════════════════════════╣${reset}"
        echo -e "${pur}║${reset}  Новая версия : ${green}${NEW_VERSION}${reset}"
        echo -e "${pur}║${reset}  Пакетов      : ${orange}${TOTAL_PKGS}${reset}"
        echo -e "${pur}║${reset}  Лог          : ${blue}/tmp/log_update.log${reset}"
        echo -e "${pur}╚══════════════════════════════════════════════════╝${reset}"
        echo ""
    else
        echo -e "${red}Ошибка обновления. Код возврата: $EXIT_CODE${reset}"
        echo -e "${red}Полный лог: /tmp/log_update.log${reset}"
        exit "$EXIT_CODE"
    fi
}

auto_update() {
    title_menu auto
    sys_info
    echo -e "${blue}Обновление по текущему ${orange}$SOURCES${reset}"

    check_sources_versions || exit 1
    safe_apt_update || exit 1

    TOTAL_PKGS=$(apt-get -s dist-upgrade 2>/dev/null | grep -c "^Inst " || true)
    if [ "$TOTAL_PKGS" -eq 0 ]; then
        echo -e "${pur}[ ${red}* ${pur}] ${green}Система уже обновлена. Пакетов: ${orange}0${reset}"
        exit 0
    fi
    echo "Найдено пакетов для обновления: $TOTAL_PKGS"

    run_dist_upgrade_with_progress
}

manual_update() {
    title_menu manual
    sys_info
    check_update_manual
    run_dist_upgrade_with_progress
}

zhestkaya_porka() {
    title_menu astra-update
    sys_info
    echo -e "${blue}Обновление через astra-update по текущему ${orange}$SOURCES${reset}"

    check_sources_versions || exit 1
    safe_apt_update || exit 1

    TOTAL_PKGS=$(apt-get -s dist-upgrade 2>/dev/null | grep -c "^Inst " || true)
    if [ "$TOTAL_PKGS" -eq 0 ]; then
        echo -e "${pur}[ ${red}* ${pur}] ${green}Система уже обновлена. Пакетов: ${orange}0${reset}"
        exit 0
    fi
    echo "Найдено пакетов для обновления: $TOTAL_PKGS"

    run_dist_upgrade_with_progress "astra"
}

check_update_manual() {
    echo -e "${blue}У вас установлен ${pur}update ${orange}[ ${red}$UPDATE ${orange}]${reset}"

    prompt_repo_config || exit 1

    CURRENT_FULL=$(cat /etc/astra/build_version | tr -d '[:space:]')

    if [[ "$CURRENT_FULL" == "$LATEST_FULL" ]]; then
        echo -e "${pur}[ ${red}* ${pur}] ${green}Установлена последняя версия [ $LATEST_FULL ]${reset}"
        exit 0
    fi

    AVAILABLE_VERSIONS=()
    for ver in "${VERSIONS_ORDER[@]}"; do
        sorted_first=$(printf '%s\n%s' "$CURRENT_FULL" "$ver" | sort -V | head -n1)

        if [[ "$sorted_first" == "$CURRENT_FULL" && "$ver" != "$CURRENT_FULL" ]]; then
            is_within=$(printf '%s\n%s' "$ver" "$LATEST_FULL" | sort -V | head -n1)
            if [[ "$is_within" == "$ver" ]]; then
                AVAILABLE_VERSIONS+=("$ver")
            fi
        fi
    done

    if [ ${#AVAILABLE_VERSIONS[@]} -eq 0 ]; then
        echo -e "${pur}[ ${red}* ${pur}] ${orange}Нет доступных обновлений выше $CURRENT_FULL${reset}"
        exit 0
    fi

    echo -e "${pur}[ ${red}* ${pur}] ${green}Доступные версии для обновления:${reset}"
    select SELECTED_VER in "${AVAILABLE_VERSIONS[@]}"; do
        if [ -n "$SELECTED_VER" ]; then
            echo -e "${pur}[ ${red}* ${pur}] ${green}Выбрана версия: ${orange}$SELECTED_VER${reset}"
            break
        else
            echo -e "${red}Некорректный выбор. Попробуйте снова.${reset}"
        fi
    done

    TARGET_REPO="${REPO_MAP[$SELECTED_VER]}"
    if [ -z "$TARGET_REPO" ]; then
        echo -e "${pur}[ ${red}* ${pur}] ${red}ERROR: Для версии $SELECTED_VER не задан каталог репозитория в REPO_MAP${reset}"
        exit 1
    fi

    local BACKUP_FILE="${SOURCES}.back.$(date +%Y%m%d%H%M%S)"
    if [[ -f "$SOURCES" ]]; then
        cp "$SOURCES" "$BACKUP_FILE"
        echo -e "${pur}[ ${red}* ${pur}] ${green}Бэкап sources.list: ${orange}$BACKUP_FILE${reset}"
    fi

    generate_sources_for_version "$TARGET_REPO" || exit 1
    safe_apt_update || exit 1

    TOTAL_PKGS=$(apt-get -s dist-upgrade 2>/dev/null | grep -c "^Inst " || true)
    if [ "$TOTAL_PKGS" -eq 0 ]; then
        echo -e "${pur}[ ${red}* ${pur}] ${green}Система уже обновлена. Пакетов: ${orange}0${reset}"
        exit 0
    fi

    echo -e "${pur}[ ${red}* ${pur}] ${green}Обновление до ${orange}$SELECTED_VER ${green}(${orange}$TOTAL_PKGS ${green}пакетов)${reset}"
}

sys_info() {
    WIDTH=54
    SEP=$(printf '+%s+\n' "$(printf '%0.s-' $(seq 1 $((WIDTH-2))))")
    TITLE="ASTRA LINUX SYSTEM INFO"
    PAD_TITLE=$(( (WIDTH - 2 - ${#TITLE}) / 2 ))
    
    print_row() {
    local label="$1"
    local value="$2"
    printf '|  %-12s : %-'$((WIDTH - 16))'s |\n' "$label" "$value"
    }
    
    echo -e "${red}$SEP${green}"
    printf '|%*s%s%*s|\n' "$PAD_TITLE" '' "$TITLE" "$PAD_TITLE" ''
    echo -e "${red}$SEP${blue}"
    print_row "Система"       "$OS_NAME"
    print_row "Релиз"        "$OS_UPDATE"
    print_row "Имя"          "$S_NAME"
    print_row "Версия ОС"    "$OS_VERSION"
    echo -e "${red}$SEP${reset}"
}


#log_check_dir
# log "start"
# log "Логирование"

while [[ $# -gt 0 ]]; do
    case "$1" in
        -u)
            auto_update
            break
            ;;
        -m)
            manual_update
            break
            ;;
        -a)
            zhestkaya_porka
            break
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Неизвестный ключ: $1" >&2
            echo "Используйте '$SCRIPT_NAME --help' для справки." >&2
            exit 1
            ;;
    esac
done

if [[ $# -eq 0 ]]; then
    show_help
    exit 0
fi

# log "Скрипт завершил свою работу."
# log "end"