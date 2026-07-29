#!/usr/bin/env bash
#
# Ubuntu Update Manager
# Installs and manages scheduled Ubuntu package updates through cron.
#
# Usage:
#   sudo bash ubuntu-update-manager.sh install
#   sudo ubuntu-update-manager status
#   sudo ubuntu-update-manager enable
#   sudo ubuntu-update-manager disable
#   sudo ubuntu-update-manager set-frequency weekly sunday 03:17
#

set -Eeuo pipefail

PROGRAM_NAME="ubuntu-update-manager"
PROGRAM_VERSION="1.1.0"
INSTALL_PATH="/usr/local/sbin/${PROGRAM_NAME}"
CONFIG_PATH="/etc/default/${PROGRAM_NAME}"
CRON_PATH="/etc/cron.d/${PROGRAM_NAME}"
LOG_PATH="/var/log/${PROGRAM_NAME}.log"
LOGROTATE_PATH="/etc/logrotate.d/${PROGRAM_NAME}"
LOCK_PATH="/run/lock/${PROGRAM_NAME}.lock"
STATE_DIR="/var/lib/${PROGRAM_NAME}"
STATE_PATH="${STATE_DIR}/status"
SCRIPT_PATH="$(readlink -f "$0")"

# Defaults used during the first installation.
DEFAULT_ENABLED="yes"
DEFAULT_FREQUENCY="weekly"
DEFAULT_RUN_TIME="03:17"
DEFAULT_RUN_DAY="0"
DEFAULT_CRON_EXPRESSION="17 3 * * 0"
DEFAULT_UPDATE_MODE="safe"
DEFAULT_AUTO_REBOOT="no"
DEFAULT_INCLUDE_SNAPS="yes"
DEFAULT_NOTIFY_EMAIL=""

ENABLED="$DEFAULT_ENABLED"
FREQUENCY="$DEFAULT_FREQUENCY"
RUN_TIME="$DEFAULT_RUN_TIME"
RUN_DAY="$DEFAULT_RUN_DAY"
CRON_EXPRESSION="$DEFAULT_CRON_EXPRESSION"
UPDATE_MODE="$DEFAULT_UPDATE_MODE"
AUTO_REBOOT="$DEFAULT_AUTO_REBOOT"
INCLUDE_SNAPS="$DEFAULT_INCLUDE_SNAPS"
NOTIFY_EMAIL="$DEFAULT_NOTIFY_EMAIL"

usage() {
    cat <<'EOF'
Ubuntu Update Manager

Usage:
  ubuntu-update-manager <command> [options]

Commands:
  install
      Install or update the manager. Existing settings are preserved.

  enable
      Enable scheduled updates.

  disable
      Disable scheduled updates without removing the manager.

  status
      Show the current configuration and cron service status.

  run
      Check for and install updates immediately.

  set-frequency daily [HH:MM]
      Run every day. Example:
      ubuntu-update-manager set-frequency daily 03:17

  set-frequency weekly [DAY] [HH:MM]
      Run once a week. DAY may be sunday through saturday or 0 through 6.
      Example:
      ubuntu-update-manager set-frequency weekly sunday 03:17

  set-frequency monthly [DAY_OF_MONTH] [HH:MM]
      Run once a month. DAY_OF_MONTH must be 1 through 28.
      Example:
      ubuntu-update-manager set-frequency monthly 1 03:17

  set-schedule "CRON_EXPRESSION"
      Use a custom five-field cron schedule.
      Example:
      ubuntu-update-manager set-schedule "30 2 * * 1,4"

  set-mode safe|full
      safe: Upgrade packages without removing installed packages.
      full: Allow dependency changes and package removals when required.

  set-reboot on|off
      Enable or disable automatic rebooting when updates require it.
      Automatic rebooting is disabled by default.

  set-snaps on|off
      Enable or disable Snap refreshes during scheduled update runs.

  set-email ADDRESS|off
      Send update failure details when local mail delivery is configured.
      Use "off" to disable email delivery.

  logs [LINES]
      Display the update log. The default is the last 100 lines.

  menu
      Open the interactive management menu.

  uninstall
      Remove the manager, configuration, and cron job.
      The update log is retained.

  version
      Display the installed manager version.

  help
      Display this help.

Default schedule:
  Every Sunday at 03:17, using the server's local timezone.
EOF
}

info() {
    printf '%s\n' "$*"
}

warn() {
    printf 'Warning: %s\n' "$*" >&2
}

die() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

require_root() {
    if (( EUID != 0 )); then
        die "This command requires root privileges. Run it with sudo."
    fi
}

normalize_on_off() {
    case "${1,,}" in
        on|yes|true|1|enabled)
            printf 'yes\n'
            ;;
        off|no|false|0|disabled)
            printf 'no\n'
            ;;
        *)
            return 1
            ;;
    esac
}

set_config_defaults() {
    ENABLED="$DEFAULT_ENABLED"
    FREQUENCY="$DEFAULT_FREQUENCY"
    RUN_TIME="$DEFAULT_RUN_TIME"
    RUN_DAY="$DEFAULT_RUN_DAY"
    CRON_EXPRESSION="$DEFAULT_CRON_EXPRESSION"
    UPDATE_MODE="$DEFAULT_UPDATE_MODE"
    AUTO_REBOOT="$DEFAULT_AUTO_REBOOT"
    INCLUDE_SNAPS="$DEFAULT_INCLUDE_SNAPS"
    NOTIFY_EMAIL="$DEFAULT_NOTIFY_EMAIL"
}

decode_legacy_config_value() {
    local value="$1"
    local decoded=""
    local character
    local index
    local escaped="no"

    # v1.0 used printf %q. Its allowed values only require removal of
    # single-character backslash escaping. No value is evaluated as shell code.
    for (( index = 0; index < ${#value}; index++ )); do
        character="${value:index:1}"
        if [[ "$escaped" == "yes" ]]; then
            decoded+="$character"
            escaped="no"
        elif [[ "$character" == '\' ]]; then
            escaped="yes"
        else
            decoded+="$character"
        fi
    done

    [[ "$escaped" == "no" ]] ||
        die "Invalid trailing escape in ${CONFIG_PATH}."
    printf '%s\n' "$decoded"
}

validate_email() {
    local value="$1"

    [[ -z "$value" ||
        "$value" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,63}$ ]] ||
        die "Notification email must be a valid single email address or off."
}

validate_cron_field() {
    local field="$1"
    local minimum="$2"
    local maximum="$3"
    local field_name="$4"
    local item base step start end
    local -a items

    [[ -n "$field" ]] || die "The ${field_name} cron field is empty."
    IFS=',' read -r -a items <<<"$field"

    for item in "${items[@]}"; do
        [[ -n "$item" ]] ||
            die "The ${field_name} cron field contains an empty list item."

        base="$item"
        step=""
        if [[ "$item" == */* ]]; then
            [[ "$item" != */*/* ]] ||
                die "The ${field_name} cron field contains too many slashes."
            base="${item%/*}"
            step="${item##*/}"
            [[ "$step" =~ ^[0-9]+$ ]] ||
                die "The ${field_name} cron step must be a positive number."
            (( ${#step} <= 6 )) ||
                die "The ${field_name} cron step is unreasonably large."
            (( 10#$step > 0 )) ||
                die "The ${field_name} cron step cannot be zero."
            [[ "$base" == "*" || "$base" == *-* ]] ||
                die "A ${field_name} cron step must follow * or a range."
        fi

        if [[ "$base" == "*" ]]; then
            continue
        fi

        if [[ "$base" == *-* ]]; then
            [[ "$base" != *-*-* ]] ||
                die "The ${field_name} cron field contains an invalid range."
            start="${base%-*}"
            end="${base#*-}"
            [[ "$start" =~ ^[0-9]+$ && "$end" =~ ^[0-9]+$ ]] ||
                die "The ${field_name} cron range must contain numbers."
            (( ${#start} <= 3 && ${#end} <= 3 )) ||
                die "The ${field_name} cron range contains an oversized number."
            (( 10#$start >= minimum && 10#$start <= maximum &&
                10#$end >= minimum && 10#$end <= maximum )) ||
                die "The ${field_name} cron range must be within ${minimum}-${maximum}."
            (( 10#$start <= 10#$end )) ||
                die "The ${field_name} cron range cannot run backward."
        else
            [[ "$base" =~ ^[0-9]+$ ]] ||
                die "The ${field_name} cron field contains an invalid value."
            (( ${#base} <= 3 )) ||
                die "The ${field_name} cron field contains an oversized number."
            (( 10#$base >= minimum && 10#$base <= maximum )) ||
                die "The ${field_name} cron value must be within ${minimum}-${maximum}."
        fi
    done
}

validate_cron_expression() {
    local expression="$1"
    local -a fields

    [[ "$expression" != *$'\n'* && "$expression" != *$'\r'* ]] ||
        die "The cron schedule must be a single line."
    [[ "$expression" =~ ^[0-9*/,\ -]+$ ]] ||
        die "The cron schedule contains unsupported characters."

    read -r -a fields <<<"$expression"
    (( ${#fields[@]} == 5 )) ||
        die "A custom schedule must contain exactly five cron fields."

    validate_cron_field "${fields[0]}" 0 59 "minute"
    validate_cron_field "${fields[1]}" 0 23 "hour"
    validate_cron_field "${fields[2]}" 1 31 "day-of-month"
    validate_cron_field "${fields[3]}" 1 12 "month"
    validate_cron_field "${fields[4]}" 0 7 "day-of-week"
}

validate_config_values() {
    local hour minute expected_expression=""

    [[ "$ENABLED" == "yes" || "$ENABLED" == "no" ]] ||
        die "Invalid ENABLED value in ${CONFIG_PATH}."

    case "$FREQUENCY" in
        daily|weekly|monthly|custom) ;;
        *) die "Invalid FREQUENCY value in ${CONFIG_PATH}." ;;
    esac

    # v1.0 replaced these retained defaults with the literal word "custom".
    if [[ "$FREQUENCY" == "custom" && "$RUN_TIME" == "custom" ]]; then
        RUN_TIME="$DEFAULT_RUN_TIME"
    fi
    if [[ "$FREQUENCY" == "custom" && "$RUN_DAY" == "custom" ]]; then
        RUN_DAY="$DEFAULT_RUN_DAY"
    fi

    read -r hour minute < <(validate_time "$RUN_TIME")
    hour="$((10#$hour))"
    minute="$((10#$minute))"

    case "$FREQUENCY" in
        daily)
            [[ "$RUN_DAY" == "*" ]] ||
                die "RUN_DAY must be * for a daily schedule."
            expected_expression="${minute} ${hour} * * *"
            ;;
        weekly)
            [[ "$RUN_DAY" =~ ^[0-6]$ ]] ||
                die "RUN_DAY must be 0 through 6 for a weekly schedule."
            expected_expression="${minute} ${hour} * * ${RUN_DAY}"
            ;;
        monthly)
            [[ "$RUN_DAY" =~ ^[0-9]+$ ]] &&
                (( 10#$RUN_DAY >= 1 && 10#$RUN_DAY <= 28 )) ||
                die "RUN_DAY must be 1 through 28 for a monthly schedule."
            expected_expression="${minute} ${hour} $((10#$RUN_DAY)) * *"
            ;;
        custom)
            [[ "$RUN_DAY" == "*" ||
                ( "$RUN_DAY" =~ ^[0-9]{1,2}$ &&
                10#$RUN_DAY -ge 0 && 10#$RUN_DAY -le 28 ) ]] ||
                die "Invalid retained RUN_DAY in ${CONFIG_PATH}."
            ;;
    esac

    validate_cron_expression "$CRON_EXPRESSION"
    if [[ -n "$expected_expression" &&
        "$CRON_EXPRESSION" != "$expected_expression" ]]; then
        die "CRON_EXPRESSION does not match the configured ${FREQUENCY} schedule."
    fi
    [[ "$UPDATE_MODE" == "safe" || "$UPDATE_MODE" == "full" ]] ||
        die "Invalid UPDATE_MODE value in ${CONFIG_PATH}."
    [[ "$AUTO_REBOOT" == "yes" || "$AUTO_REBOOT" == "no" ]] ||
        die "Invalid AUTO_REBOOT value in ${CONFIG_PATH}."
    [[ "$INCLUDE_SNAPS" == "yes" || "$INCLUDE_SNAPS" == "no" ]] ||
        die "Invalid INCLUDE_SNAPS value in ${CONFIG_PATH}."
    validate_email "$NOTIFY_EMAIL"
}

check_config_file_security() {
    local owner mode

    [[ -f "$CONFIG_PATH" && ! -L "$CONFIG_PATH" ]] ||
        die "${CONFIG_PATH} must be a regular file, not a symbolic link."
    owner="$(stat -c '%u' "$CONFIG_PATH")"
    mode="$(stat -c '%a' "$CONFIG_PATH")"
    [[ "$owner" == "0" ]] ||
        die "${CONFIG_PATH} must be owned by root."

    (( (8#$mode & 0022) == 0 )) ||
        die "${CONFIG_PATH} must not be group/world writable."
}

load_config() {
    local line key raw_value value
    local -A seen=()

    set_config_defaults
    [[ -e "$CONFIG_PATH" ]] || return 0
    [[ -r "$CONFIG_PATH" ]] ||
        die "Cannot read ${CONFIG_PATH}."
    check_config_file_security

    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" || "$line" == \#* ]] && continue
        [[ "$line" != *$'\r'* && "$line" != *$'\n'* ]] ||
            die "Invalid line ending in ${CONFIG_PATH}."
        [[ "$line" =~ ^([A-Z_]+)=(.*)$ ]] ||
            die "Invalid configuration line in ${CONFIG_PATH}: ${line}"

        key="${BASH_REMATCH[1]}"
        raw_value="${BASH_REMATCH[2]}"
        [[ -z "${seen[$key]+x}" ]] ||
            die "Duplicate ${key} entry in ${CONFIG_PATH}."
        seen["$key"]=1
        value="$(decode_legacy_config_value "$raw_value")"

        case "$key" in
            ENABLED) ENABLED="$value" ;;
            FREQUENCY) FREQUENCY="$value" ;;
            RUN_TIME) RUN_TIME="$value" ;;
            RUN_DAY) RUN_DAY="$value" ;;
            CRON_EXPRESSION) CRON_EXPRESSION="$value" ;;
            UPDATE_MODE) UPDATE_MODE="$value" ;;
            AUTO_REBOOT) AUTO_REBOOT="$value" ;;
            INCLUDE_SNAPS) INCLUDE_SNAPS="$value" ;;
            NOTIFY_EMAIL) NOTIFY_EMAIL="$value" ;;
            *) die "Unknown configuration key ${key} in ${CONFIG_PATH}." ;;
        esac
    done <"$CONFIG_PATH"

    validate_config_values
}

write_config() (
    require_root
    validate_config_values

    [[ ! -L "$CONFIG_PATH" ]] ||
        die "Refusing to replace symbolic link ${CONFIG_PATH}."

    local temp_file
    temp_file="$(mktemp "${CONFIG_PATH}.tmp.XXXXXX")"
    trap 'rm -f -- "$temp_file"' EXIT

    {
        printf '# Managed by %s. Use %s commands to edit.\n' \
            "$PROGRAM_NAME" "$PROGRAM_NAME"
        printf 'ENABLED=%s\n' "$ENABLED"
        printf 'FREQUENCY=%s\n' "$FREQUENCY"
        printf 'RUN_TIME=%s\n' "$RUN_TIME"
        printf 'RUN_DAY=%s\n' "$RUN_DAY"
        printf 'CRON_EXPRESSION=%s\n' "$CRON_EXPRESSION"
        printf 'UPDATE_MODE=%s\n' "$UPDATE_MODE"
        printf 'AUTO_REBOOT=%s\n' "$AUTO_REBOOT"
        printf 'INCLUDE_SNAPS=%s\n' "$INCLUDE_SNAPS"
        printf 'NOTIFY_EMAIL=%s\n' "$NOTIFY_EMAIL"
    } >"$temp_file"

    chown root:root "$temp_file"
    chmod 0644 "$temp_file"
    mv -f -- "$temp_file" "$CONFIG_PATH"
    trap - EXIT
)

render_cron() (
    require_root
    validate_config_values

    [[ ! -L "$CRON_PATH" ]] ||
        die "Refusing to replace symbolic link ${CRON_PATH}."

    local temp_file
    temp_file="$(mktemp "${CRON_PATH}.tmp.XXXXXX")"
    trap 'rm -f -- "$temp_file"' EXIT

    {
        printf 'SHELL=/bin/bash\n'
        printf 'PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\n'
        printf 'MAILTO=""\n\n'

        if [[ "$ENABLED" == "yes" ]]; then
            printf '%s root %s run --scheduled\n' "$CRON_EXPRESSION" "$INSTALL_PATH"
        else
            printf '# Scheduled Ubuntu updates are disabled.\n'
        fi
    } >"$temp_file"

    chown root:root "$temp_file"
    chmod 0644 "$temp_file"
    mv -f -- "$temp_file" "$CRON_PATH"
    trap - EXIT
)

log_group() {
    if getent group adm >/dev/null 2>&1; then
        printf 'adm\n'
    else
        printf 'root\n'
    fi
}

ensure_log_file() {
    require_root

    local group
    group="$(log_group)"
    touch "$LOG_PATH"
    chown "root:${group}" "$LOG_PATH"
    chmod 0640 "$LOG_PATH"
}

render_logrotate() (
    require_root

    [[ ! -L "$LOGROTATE_PATH" ]] ||
        die "Refusing to replace symbolic link ${LOGROTATE_PATH}."

    local temp_file group
    group="$(log_group)"
    temp_file="$(mktemp "${LOGROTATE_PATH}.tmp.XXXXXX")"
    trap 'rm -f -- "$temp_file"' EXIT

    {
        printf '%s {\n' "$LOG_PATH"
        printf '    weekly\n'
        printf '    rotate 12\n'
        printf '    compress\n'
        printf '    delaycompress\n'
        printf '    missingok\n'
        printf '    notifempty\n'
        printf '    create 0640 root %s\n' "$group"
        printf '}\n'
    } >"$temp_file"

    chown root:root "$temp_file"
    chmod 0644 "$temp_file"
    mv -f -- "$temp_file" "$LOGROTATE_PATH"
    trap - EXIT
)

write_run_state() (
    local result="$1"
    local exit_code="$2"
    local started_at="$3"
    local finished_at="$4"
    local duration="$5"
    local temp_file previous_success="" previous_failure=""
    local line key value

    require_root
    install -d -o root -g root -m 0755 "$STATE_DIR"

    if [[ -f "$STATE_PATH" && ! -L "$STATE_PATH" ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            [[ "$line" =~ ^([A-Z_]+)=(.*)$ ]] || continue
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
            case "$key" in
                LAST_SUCCESS_AT) previous_success="$value" ;;
                LAST_FAILURE_AT) previous_failure="$value" ;;
            esac
        done <"$STATE_PATH"
    fi

    if [[ "$result" == "success" ]]; then
        previous_success="$finished_at"
    else
        previous_failure="$finished_at"
    fi

    [[ ! -L "$STATE_PATH" ]] ||
        die "Refusing to replace symbolic link ${STATE_PATH}."
    temp_file="$(mktemp "${STATE_PATH}.tmp.XXXXXX")"
    trap 'rm -f -- "$temp_file"' EXIT

    {
        printf 'LAST_RUN_STARTED_AT=%s\n' "$started_at"
        printf 'LAST_RUN_FINISHED_AT=%s\n' "$finished_at"
        printf 'LAST_RESULT=%s\n' "$result"
        printf 'LAST_EXIT_CODE=%s\n' "$exit_code"
        printf 'LAST_DURATION_SECONDS=%s\n' "$duration"
        printf 'LAST_SUCCESS_AT=%s\n' "$previous_success"
        printf 'LAST_FAILURE_AT=%s\n' "$previous_failure"
    } >"$temp_file"

    chown root:root "$temp_file"
    chmod 0644 "$temp_file"
    mv -f -- "$temp_file" "$STATE_PATH"
    trap - EXIT
)

show_run_state() {
    local last_started="never"
    local last_finished="never"
    local last_result="never"
    local last_exit="n/a"
    local last_duration="n/a"
    local last_success="never"
    local last_failure="never"
    local line key value

    if [[ -r "$STATE_PATH" && -f "$STATE_PATH" && ! -L "$STATE_PATH" ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            [[ "$line" =~ ^([A-Z_]+)=(.*)$ ]] || continue
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
            case "$key" in
                LAST_RUN_STARTED_AT) last_started="${value:-never}" ;;
                LAST_RUN_FINISHED_AT) last_finished="${value:-never}" ;;
                LAST_RESULT) last_result="${value:-never}" ;;
                LAST_EXIT_CODE) last_exit="${value:-n/a}" ;;
                LAST_DURATION_SECONDS) last_duration="${value:-n/a}" ;;
                LAST_SUCCESS_AT) last_success="${value:-never}" ;;
                LAST_FAILURE_AT) last_failure="${value:-never}" ;;
            esac
        done <"$STATE_PATH"
    fi

    info "Last run:         ${last_started}"
    info "Last result:      ${last_result} (exit ${last_exit}, ${last_duration}s)"
    info "Last success:     ${last_success}"
    info "Last failure:     ${last_failure}"
    if [[ "$last_finished" != "never" ]]; then
        info "Last finished:    ${last_finished}"
    fi
}

ensure_installed() {
    [[ -x "$INSTALL_PATH" ]] ||
        die "The manager is not installed. Run: sudo bash $SCRIPT_PATH install"
    [[ -r "$CONFIG_PATH" ]] ||
        die "Configuration is missing. Reinstall the manager."
}

validate_time() {
    local value="$1"
    local hour minute

    [[ "$value" =~ ^([01][0-9]|2[0-3]):([0-5][0-9])$ ]] ||
        die "Time must use 24-hour HH:MM format."

    hour="${BASH_REMATCH[1]}"
    minute="${BASH_REMATCH[2]}"
    printf '%s %s\n' "$hour" "$minute"
}

weekday_number() {
    case "${1,,}" in
        0|sun|sunday) printf '0\n' ;;
        1|mon|monday) printf '1\n' ;;
        2|tue|tues|tuesday) printf '2\n' ;;
        3|wed|wednesday) printf '3\n' ;;
        4|thu|thur|thurs|thursday) printf '4\n' ;;
        5|fri|friday) printf '5\n' ;;
        6|sat|saturday) printf '6\n' ;;
        *) return 1 ;;
    esac
}

weekday_name() {
    case "$1" in
        0) printf 'Sunday\n' ;;
        1) printf 'Monday\n' ;;
        2) printf 'Tuesday\n' ;;
        3) printf 'Wednesday\n' ;;
        4) printf 'Thursday\n' ;;
        5) printf 'Friday\n' ;;
        6) printf 'Saturday\n' ;;
        *) printf '%s\n' "$1" ;;
    esac
}

cron_service_active() {
    if command -v systemctl >/dev/null 2>&1 &&
        [[ "$(ps -p 1 -o comm= 2>/dev/null)" == "systemd" ]]; then
        systemctl is-active --quiet cron 2>/dev/null
    else
        pgrep -x cron >/dev/null 2>&1
    fi
}

ensure_cron_service() {
    require_root

    local -a packages=()
    command -v cron >/dev/null 2>&1 || packages+=(cron)
    command -v logrotate >/dev/null 2>&1 || packages+=(logrotate)

    if (( ${#packages[@]} > 0 )); then
        info "Installing required packages: ${packages[*]}"
        export DEBIAN_FRONTEND=noninteractive
        apt-get \
            -o DPkg::Lock::Timeout=300 \
            -o Acquire::Retries=3 \
            -o APT::Update::Error-Mode=any \
            update
        apt-get \
            -y \
            -o DPkg::Lock::Timeout=300 \
            -o Acquire::Retries=3 \
            install "${packages[@]}"
    fi

    if command -v systemctl >/dev/null 2>&1 &&
        [[ "$(ps -p 1 -o comm= 2>/dev/null)" == "systemd" ]]; then
        systemctl enable --now cron
    elif command -v service >/dev/null 2>&1; then
        service cron start >/dev/null
    fi

    cron_service_active ||
        die "The cron service could not be started or verified."
}

install_program_file() (
    require_root

    install -d -o root -g root -m 0755 "$(dirname "$INSTALL_PATH")"

    if [[ "$SCRIPT_PATH" == "$INSTALL_PATH" ]]; then
        chown root:root "$INSTALL_PATH"
        chmod 0750 "$INSTALL_PATH"
        return
    fi

    [[ ! -L "$INSTALL_PATH" ]] ||
        die "Refusing to replace symbolic link ${INSTALL_PATH}."

    local temp_file
    temp_file="$(mktemp "${INSTALL_PATH}.tmp.XXXXXX")"
    trap 'rm -f -- "$temp_file"' EXIT
    install -o root -g root -m 0750 "$SCRIPT_PATH" "$temp_file"
    mv -f -- "$temp_file" "$INSTALL_PATH"
    trap - EXIT
)

install_manager() {
    require_root
    local preserving_config="no"

    [[ -f "$SCRIPT_PATH" ]] || die "Cannot locate the source script."

    if [[ -e "$CONFIG_PATH" ]]; then
        load_config
        preserving_config="yes"
    else
        set_config_defaults
    fi

    ensure_cron_service
    install_program_file
    write_config
    if [[ "$preserving_config" == "yes" ]]; then
        info "Preserving the existing configuration."
    fi

    render_cron
    ensure_log_file
    render_logrotate
    install -d -o root -g root -m 0755 "$STATE_DIR"
    install -d -o root -g root -m 0755 "$(dirname "$LOCK_PATH")"

    info
    info "Ubuntu Update Manager ${PROGRAM_VERSION} is installed."
    show_status
    info
    info "Run '${PROGRAM_NAME} menu' for interactive management."
}

enable_updates() {
    require_root
    ensure_installed
    load_config
    ENABLED="yes"
    write_config
    render_cron
    info "Scheduled Ubuntu updates are enabled."
    show_schedule
}

disable_updates() {
    require_root
    ensure_installed
    load_config
    ENABLED="no"
    write_config
    render_cron
    info "Scheduled Ubuntu updates are disabled."
}

show_schedule() {
    case "$FREQUENCY" in
        daily)
            info "Schedule: Every day at ${RUN_TIME}"
            ;;
        weekly)
            info "Schedule: Every $(weekday_name "$RUN_DAY") at ${RUN_TIME}"
            ;;
        monthly)
            info "Schedule: Day ${RUN_DAY} of each month at ${RUN_TIME}"
            ;;
        custom)
            info "Schedule: ${CRON_EXPRESSION}"
            ;;
        *)
            info "Schedule: ${CRON_EXPRESSION}"
            ;;
    esac
}

show_status() {
    load_config

    info "Ubuntu Update Manager ${PROGRAM_VERSION}"
    info "Installed:       $([[ -x "$INSTALL_PATH" ]] && printf 'yes' || printf 'no')"
    info "Enabled:         ${ENABLED}"
    show_schedule
    info "Cron expression: ${CRON_EXPRESSION}"
    info "Update mode:     ${UPDATE_MODE}"
    info "Snap updates:    ${INCLUDE_SNAPS}"
    info "Automatic reboot: ${AUTO_REBOOT}"
    info "Failure email:   ${NOTIFY_EMAIL:-disabled}"
    info "Log file:        ${LOG_PATH}"
    info "Log rotation:    weekly, 12 archives"
    show_run_state

    if cron_service_active; then
        info "Cron service:    active"
    else
        warn "The cron service is not active."
    fi

    if command -v systemctl >/dev/null 2>&1 &&
        [[ "$(ps -p 1 -o comm= 2>/dev/null)" == "systemd" ]]; then
        if systemctl is-active --quiet apt-daily.timer 2>/dev/null ||
            systemctl is-active --quiet apt-daily-upgrade.timer 2>/dev/null; then
            warn "Ubuntu APT background timers are active; update runs will wait up to 5 minutes for APT locks."
        fi
        if systemctl is-enabled --quiet unattended-upgrades.service 2>/dev/null; then
            warn "unattended-upgrades is enabled; review both policies to avoid overlapping update behavior."
        fi
    fi

    if [[ -n "$NOTIFY_EMAIL" && ! -x /usr/sbin/sendmail ]]; then
        warn "Failure email is configured, but no local sendmail-compatible service was detected."
    fi

    if [[ -f /var/run/reboot-required ]]; then
        warn "The server currently requires a reboot."
    fi
}

set_frequency() {
    require_root
    ensure_installed
    load_config

    local frequency="${1:-}"
    local hour minute hour_number minute_number day time_value

    case "${frequency,,}" in
        daily)
            time_value="${2:-$RUN_TIME}"
            read -r hour minute < <(validate_time "$time_value")
            hour_number="$((10#$hour))"
            minute_number="$((10#$minute))"
            FREQUENCY="daily"
            RUN_TIME="$time_value"
            RUN_DAY="*"
            CRON_EXPRESSION="${minute_number} ${hour_number} * * *"
            ;;

        weekly)
            day="$(weekday_number "${2:-sunday}")" ||
                die "Invalid weekday. Use sunday through saturday or 0 through 6."
            time_value="${3:-$RUN_TIME}"
            read -r hour minute < <(validate_time "$time_value")
            hour_number="$((10#$hour))"
            minute_number="$((10#$minute))"
            FREQUENCY="weekly"
            RUN_TIME="$time_value"
            RUN_DAY="$day"
            CRON_EXPRESSION="${minute_number} ${hour_number} * * ${day}"
            ;;

        monthly)
            day="${2:-1}"
            [[ "$day" =~ ^[0-9]+$ ]] ||
                die "The monthly day must be a number from 1 through 28."
            (( 10#$day >= 1 && 10#$day <= 28 )) ||
                die "The monthly day must be from 1 through 28."
            time_value="${3:-$RUN_TIME}"
            read -r hour minute < <(validate_time "$time_value")
            hour_number="$((10#$hour))"
            minute_number="$((10#$minute))"
            FREQUENCY="monthly"
            RUN_TIME="$time_value"
            RUN_DAY="$((10#$day))"
            CRON_EXPRESSION="${minute_number} ${hour_number} ${RUN_DAY} * *"
            ;;

        *)
            die "Frequency must be daily, weekly, or monthly."
            ;;
    esac

    write_config
    render_cron
    info "Update frequency changed."
    show_schedule
}

set_custom_schedule() {
    require_root
    ensure_installed
    load_config

    local expression="${1:-}"
    [[ -n "$expression" ]] || die "Provide a five-field cron expression."
    validate_cron_expression "$expression"

    FREQUENCY="custom"
    CRON_EXPRESSION="$expression"
    write_config
    render_cron

    info "Custom update schedule saved: ${CRON_EXPRESSION}"
}

set_update_mode() {
    require_root
    ensure_installed
    load_config

    case "${1:-}" in
        safe|full)
            UPDATE_MODE="$1"
            ;;
        *)
            die "Update mode must be safe or full."
            ;;
    esac

    write_config
    info "Update mode set to ${UPDATE_MODE}."
}

set_reboot() {
    require_root
    ensure_installed
    load_config

    AUTO_REBOOT="$(normalize_on_off "${1:-}")" ||
        die "Automatic reboot must be on or off."
    write_config
    info "Automatic reboot: ${AUTO_REBOOT}"
}

set_snaps() {
    require_root
    ensure_installed
    load_config

    INCLUDE_SNAPS="$(normalize_on_off "${1:-}")" ||
        die "Snap updates must be on or off."
    write_config
    info "Snap updates: ${INCLUDE_SNAPS}"
}

set_email() {
    require_root
    ensure_installed
    load_config

    case "${1:-}" in
        off|none|disabled)
            NOTIFY_EMAIL=""
            ;;
        "")
            die "Provide an email address or off."
            ;;
        *)
            validate_email "$1"
            NOTIFY_EMAIL="$1"
            ;;
    esac

    write_config
    render_cron
    info "Failure email: ${NOTIFY_EMAIL:-disabled}"
    if [[ -n "$NOTIFY_EMAIL" && ! -x /usr/sbin/sendmail ]]; then
        warn "Install and configure a sendmail-compatible mail service for delivery."
    fi
}

send_failure_notification() {
    local exit_code="$1"
    local line_number="$2"
    local started_at="$3"
    local finished_at="$4"
    local host

    [[ -n "$NOTIFY_EMAIL" ]] || return 0
    if [[ ! -x /usr/sbin/sendmail ]]; then
        warn "Failure email was not sent because /usr/sbin/sendmail is unavailable."
        return 0
    fi

    host="$(hostname -f 2>/dev/null || hostname)"
    {
        printf 'To: %s\n' "$NOTIFY_EMAIL"
        printf 'Subject: [%s] Ubuntu update failed on %s\n' "$PROGRAM_NAME" "$host"
        printf 'Content-Type: text/plain; charset=UTF-8\n'
        printf '\n'
        printf 'Ubuntu Update Manager reported a failed update run.\n\n'
        printf 'Host: %s\n' "$host"
        printf 'Started: %s\n' "$started_at"
        printf 'Finished: %s\n' "$finished_at"
        printf 'Exit code: %s\n' "$exit_code"
        printf 'Approximate script line: %s\n' "$line_number"
        printf 'Log: %s\n\n' "$LOG_PATH"
        printf 'Last 80 log lines:\n'
        tail -n 80 "$LOG_PATH" 2>/dev/null || true
    } | /usr/sbin/sendmail -t
}

update_failed() {
    local exit_code="$1"
    local line_number="$2"
    local start_epoch="$3"
    local started_at="$4"
    local finish_epoch finished_at duration

    trap - ERR
    set +e
    finish_epoch="$(date +%s)"
    finished_at="$(date --iso-8601=seconds)"
    duration="$((finish_epoch - start_epoch))"
    write_run_state \
        "failure" "$exit_code" "$started_at" "$finished_at" "$duration"
    logger -t "$PROGRAM_NAME" \
        "Update run failed with exit code ${exit_code} near line ${line_number}."
    info "Ubuntu update failed with exit code ${exit_code}."
    info "Review ${LOG_PATH} for details."
    send_failure_notification \
        "$exit_code" "$line_number" "$started_at" "$finished_at"
    exit "$exit_code"
}

perform_updates() (
    require_root
    ensure_installed
    load_config

    local scheduled="${1:-no}"
    local start_epoch started_at finish_epoch finished_at duration

    if [[ "$scheduled" == "yes" && "$ENABLED" != "yes" ]]; then
        exit 0
    fi

    exec 9>"$LOCK_PATH"
    if ! flock -n 9; then
        info "Another update run is already in progress."
        exit 0
    fi

    ensure_log_file
    exec > >(tee -a "$LOG_PATH") 2>&1
    start_epoch="$(date +%s)"
    started_at="$(date --iso-8601=seconds)"
    trap 'update_failed "$?" "$LINENO" "$start_epoch" "$started_at"' ERR

    info
    info "============================================================"
    info "Ubuntu update started: ${started_at}"
    info "Mode: ${UPDATE_MODE}; Snap updates: ${INCLUDE_SNAPS}"
    info "============================================================"

    export DEBIAN_FRONTEND=noninteractive
    export NEEDRESTART_MODE=a

    apt-get \
        -o DPkg::Lock::Timeout=300 \
        -o Acquire::Retries=3 \
        -o APT::Update::Error-Mode=any \
        update

    case "$UPDATE_MODE" in
        safe)
            apt-get \
                -y \
                --with-new-pkgs \
                -o DPkg::Lock::Timeout=300 \
                -o Acquire::Retries=3 \
                -o Dpkg::Options::="--force-confold" \
                upgrade
            ;;
        full)
            apt-get \
                -y \
                -o DPkg::Lock::Timeout=300 \
                -o Acquire::Retries=3 \
                -o Dpkg::Options::="--force-confold" \
                full-upgrade
            ;;
        *)
            die "Unknown update mode in ${CONFIG_PATH}: ${UPDATE_MODE}"
            ;;
    esac

    apt-get \
        -y \
        -o DPkg::Lock::Timeout=300 \
        -o Acquire::Retries=3 \
        autoclean

    if [[ "$INCLUDE_SNAPS" == "yes" ]] && command -v snap >/dev/null 2>&1; then
        snap refresh
    fi

    if [[ -f /var/run/reboot-required ]]; then
        logger -t "$PROGRAM_NAME" "Updates installed; reboot required."
        info "A reboot is required to finish installing updates."

        if [[ "$AUTO_REBOOT" == "yes" && "$scheduled" == "yes" ]]; then
            info "The server will reboot in one minute."
            shutdown -r +1 "Rebooting after scheduled Ubuntu updates"
        elif [[ "$AUTO_REBOOT" == "yes" ]]; then
            info "Automatic reboot applies only to scheduled runs; this manual run will not reboot the server."
        else
            info "Automatic rebooting is disabled."
        fi
    else
        logger -t "$PROGRAM_NAME" "Updates installed successfully."
        info "No reboot is currently required."
    fi

    finish_epoch="$(date +%s)"
    finished_at="$(date --iso-8601=seconds)"
    duration="$((finish_epoch - start_epoch))"
    write_run_state \
        "success" "0" "$started_at" "$finished_at" "$duration"
    info "Ubuntu update finished: ${finished_at} (${duration}s)"
    trap - ERR
)

show_logs() {
    local lines="${1:-100}"
    [[ "$lines" =~ ^[0-9]+$ ]] || die "Log line count must be a number."

    [[ -r "$LOG_PATH" ]] ||
        die "Cannot read ${LOG_PATH}. Try running this command with sudo."

    tail -n "$lines" "$LOG_PATH"
}

uninstall_manager() (
    require_root

    local answer="${1:-}"
    if [[ "$answer" != "--yes" ]]; then
        if [[ ! -t 0 ]]; then
            die "Run uninstall with --yes in a non-interactive shell."
        fi

        read -r -p "Remove Ubuntu Update Manager? [y/N] " answer
        [[ "${answer,,}" == "y" || "${answer,,}" == "yes" ]] || {
            info "Uninstall cancelled."
            return
        }
    fi

    install -d -o root -g root -m 0755 "$(dirname "$LOCK_PATH")"
    exec 9>"$LOCK_PATH"
    flock -n 9 ||
        die "An update run is in progress. Wait for it to finish before uninstalling."

    rm -f "$CRON_PATH"
    rm -f "$CONFIG_PATH"
    rm -f "$LOGROTATE_PATH"
    rm -f "$STATE_PATH"
    rmdir "$STATE_DIR" 2>/dev/null || true

    if [[ "$SCRIPT_PATH" == "$INSTALL_PATH" ]]; then
        rm -f "$INSTALL_PATH"
    elif [[ -f "$INSTALL_PATH" ]]; then
        rm -f "$INSTALL_PATH"
    fi

    info "Ubuntu Update Manager was removed."
    info "The existing log was retained at ${LOG_PATH}."
)

prompt_time() {
    local default_time="$1"
    local selected
    read -r -p "Run time [${default_time}]: " selected
    printf '%s\n' "${selected:-$default_time}"
}

interactive_frequency() {
    local choice day time_value month_day

    cat <<'EOF'

Select an update frequency:
  1) Daily
  2) Weekly
  3) Monthly
  4) Custom cron expression
EOF
    read -r -p "Choice: " choice

    case "$choice" in
        1)
            time_value="$(prompt_time "$RUN_TIME")"
            set_frequency daily "$time_value"
            ;;
        2)
            read -r -p "Weekday [Sunday]: " day
            time_value="$(prompt_time "$RUN_TIME")"
            set_frequency weekly "${day:-sunday}" "$time_value"
            ;;
        3)
            read -r -p "Day of month, 1 through 28 [1]: " month_day
            time_value="$(prompt_time "$RUN_TIME")"
            set_frequency monthly "${month_day:-1}" "$time_value"
            ;;
        4)
            read -r -p "Five-field cron expression: " choice
            set_custom_schedule "$choice"
            ;;
        *)
            warn "Invalid selection."
            ;;
    esac
}

interactive_menu() {
    require_root
    ensure_installed

    local choice
    while true; do
        load_config
        cat <<'EOF'

Ubuntu Update Manager
  1) Show status
  2) Enable scheduled updates
  3) Disable scheduled updates
  4) Change update frequency
  5) Run updates now
  6) Change update mode
  7) Toggle automatic reboot
  8) Toggle Snap updates
  9) View update log
  10) Configure failure email
  0) Exit
EOF
        read -r -p "Choice: " choice

        case "$choice" in
            1)
                show_status
                ;;
            2)
                enable_updates
                ;;
            3)
                disable_updates
                ;;
            4)
                interactive_frequency
                ;;
            5)
                perform_updates no
                ;;
            6)
                read -r -p "Update mode, safe or full [${UPDATE_MODE}]: " choice
                set_update_mode "${choice:-$UPDATE_MODE}"
                ;;
            7)
                if [[ "$AUTO_REBOOT" == "yes" ]]; then
                    set_reboot off
                else
                    set_reboot on
                fi
                ;;
            8)
                if [[ "$INCLUDE_SNAPS" == "yes" ]]; then
                    set_snaps off
                else
                    set_snaps on
                fi
                ;;
            9)
                show_logs 100
                ;;
            10)
                read -r -p "Failure email address or off [${NOTIFY_EMAIL:-off}]: " choice
                set_email "${choice:-${NOTIFY_EMAIL:-off}}"
                ;;
            0)
                return
                ;;
            *)
                warn "Invalid selection."
                ;;
        esac
    done
}

main() {
    local command="${1:-}"
    shift || true

    case "$command" in
        install)
            install_manager
            ;;
        enable)
            enable_updates
            ;;
        disable)
            disable_updates
            ;;
        status)
            show_status
            ;;
        run)
            if [[ "${1:-}" == "--scheduled" ]]; then
                perform_updates yes
            else
                perform_updates no
            fi
            ;;
        set-frequency)
            set_frequency "$@"
            ;;
        set-schedule)
            set_custom_schedule "${1:-}"
            ;;
        set-mode)
            set_update_mode "${1:-}"
            ;;
        set-reboot)
            set_reboot "${1:-}"
            ;;
        set-snaps)
            set_snaps "${1:-}"
            ;;
        set-email)
            set_email "${1:-}"
            ;;
        logs)
            show_logs "${1:-100}"
            ;;
        menu)
            interactive_menu
            ;;
        uninstall)
            uninstall_manager "${1:-}"
            ;;
        version|--version|-V)
            printf '%s %s\n' "$PROGRAM_NAME" "$PROGRAM_VERSION"
            ;;
        help|--help|-h)
            usage
            ;;
        "")
            if [[ -t 0 && -x "$INSTALL_PATH" ]]; then
                interactive_menu
            else
                usage
            fi
            ;;
        *)
            usage >&2
            die "Unknown command: ${command}"
            ;;
    esac
}

main "$@"
