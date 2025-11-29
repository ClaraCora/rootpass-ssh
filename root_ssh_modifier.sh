#!/usr/bin/env bash
#=============================================================
# Root Password and SSH Port Modifier
# Description: Modify root password and SSH port
#              + enable key-based login for root
#              + fetch keys from GitHub username
# Version: 1.2
# Author: Assistant
#=============================================================

VERSION=1.2
RED_FONT_PREFIX="\033[31m"
LIGHT_GREEN_FONT_PREFIX="\033[1;32m"
YELLOW_FONT_PREFIX="\033[1;33m"
BLUE_FONT_PREFIX="\033[1;34m"
FONT_COLOR_SUFFIX="\033[0m"
INFO="[${LIGHT_GREEN_FONT_PREFIX}INFO${FONT_COLOR_SUFFIX}]"
ERROR="[${RED_FONT_PREFIX}ERROR${FONT_COLOR_SUFFIX}]"
WARNING="[${YELLOW_FONT_PREFIX}WARNING${FONT_COLOR_SUFFIX}]"
SUCCESS="[${BLUE_FONT_PREFIX}SUCCESS${FONT_COLOR_SUFFIX}]"

# 检查是否为root用户
[ $EUID != 0 ] && SUDO=sudo

#---------------------- 基础工具与系统 -----------------------
detect_system() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$NAME; VER=$VERSION_ID
        # 特别处理Ubuntu系统
        if [[ "$ID" == "ubuntu" ]]; then
            OS="Ubuntu"
        fi
    elif type lsb_release >/dev/null 2>&1; then
        OS=$(lsb_release -si); VER=$(lsb_release -sr)
        # 标准化Ubuntu名称
        if [[ "$OS" == "Ubuntu" ]]; then
            OS="Ubuntu"
        fi
    elif [ -f /etc/lsb-release ]; then
        . /etc/lsb-release; OS=$DISTRIB_ID; VER=$DISTRIB_RELEASE
        # 标准化Ubuntu名称
        if [[ "$OS" == "Ubuntu" ]]; then
            OS="Ubuntu"
        fi
    elif [ -f /etc/debian_version ]; then
        OS=Debian; VER=$(cat /etc/debian_version)
    elif [ -f /etc/redhat-release ]; then
        OS=RedHat
    else
        OS=$(uname -s); VER=$(uname -r)
    fi
    echo -e "${INFO} 检测到系统: ${OS} ${VER}"
}

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        echo -e "${ERROR} 需要命令: $1"
        # 为Ubuntu系统提供安装建议
        if [[ "$OS" == "Ubuntu" ]]; then
            case "$1" in
                curl) echo -e "${INFO} 在Ubuntu上安装: sudo apt update && sudo apt install -y curl" ;;
                wget) echo -e "${INFO} 在Ubuntu上安装: sudo apt update && sudo apt install -y wget" ;;
                awk) echo -e "${INFO} 在Ubuntu上安装: sudo apt update && sudo apt install -y gawk" ;;
                *) echo -e "${INFO} 尝试安装: sudo apt update && sudo apt install -y $1" ;;
            esac
        fi
        exit 1
    }
}

# 检查并安装必要的包（Ubuntu特定）
check_ubuntu_packages() {
    if [[ "$OS" == "Ubuntu" ]]; then
        local missing_packages=()
        
        # 检查常用命令
        for cmd in curl wget awk; do
            if ! command -v "$cmd" >/dev/null 2>&1; then
                missing_packages+=("$cmd")
            fi
        done
        
        if [ ${#missing_packages[@]} -gt 0 ]; then
            echo -e "${WARNING} Ubuntu系统缺少以下命令: ${missing_packages[*]}"
            echo -e "${INFO} 可以使用以下命令安装:"
            echo -e "sudo apt update && sudo apt install -y ${missing_packages[*]}"
            read -p "是否现在安装? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                $SUDO apt update && $SUDO apt install -y "${missing_packages[@]}" || {
                    echo -e "${ERROR} 包安装失败，请手动安装"
                    exit 1
                }
            fi
        fi
    fi
}

#---------------------- 用法 -----------------------
USAGE() {
cat <<'EOF'
Root密码和SSH端口修改器 1.2

用法:
  bash root_ssh_modifier.sh [选项]

选项:
  -p <端口号>        修改SSH端口 (默认: 22)
  -r <新密码>        修改root密码
  -a                 同时修改密码和端口
  -e                 启用密码登录
  -D                 禁用密码登录，仅允许密钥
  -k <公钥或文件>    安装指定公钥(字符串或*.pub路径)
  -g <GitHub用户名>  拉取 GitHub 公钥并安装为登录密钥
  -h                 显示帮助

示例:
  bash root_ssh_modifier.sh -g alice
  bash root_ssh_modifier.sh -g alice -D
  bash root_ssh_modifier.sh -k ~/.ssh/id_ed25519.pub -p 2222
EOF
}

#---------------------- SSH 配置辅助 -----------------------
backup_sshd_once() {
    [ -f /etc/ssh/sshd_config ] || {
        echo -e "${ERROR} 未找到 /etc/ssh/sshd_config"
        # Ubuntu特定提示
        if [[ "$OS" == "Ubuntu" ]]; then
            echo -e "${INFO} 在Ubuntu系统中，SSH配置文件通常位于 /etc/ssh/sshd_config"
            echo -e "${INFO} 如果文件不存在，可能需要安装SSH服务:"
            echo -e "sudo apt update && sudo apt install -y openssh-server"
        fi
        exit 1
    }
    if [ -z "$SSHD_BACKED_UP" ]; then
        $SUDO cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup.$(date +%Y%m%d_%H%M%S)
        SSHD_BACKED_UP=1
        echo -e "${INFO} 已备份 sshd_config"
    fi
}

set_sshd_option() {
    local key="$1" val="$2"
    backup_sshd_once
    if grep -qE "^\s*${key}\s+" /etc/ssh/sshd_config; then
        $SUDO sed -i "s@^\s*${key}\s\+.*@${key} ${val}@" /etc/ssh/sshd_config
    else
        echo "${key} ${val}" | $SUDO tee -a /etc/ssh/sshd_config >/dev/null
    fi
    RESTART_SSHD=1
}

#---------------------- 账户与密钥 -----------------------
root_home() { getent passwd root | cut -d: -f6; }

install_keys_to_root() {
    # 读取 stdin 的公钥，过滤有效行，去重并写入 authorized_keys
    local RH; RH="$(root_home)"
    local SSH_DIR="${RH}/.ssh"
    local AUTH="${SSH_DIR}/authorized_keys"
    local tmp keys_filtered

    $SUDO mkdir -p "$SSH_DIR"
    $SUDO touch "$AUTH"
    $SUDO chown -R root:root "$SSH_DIR"
    $SUDO chmod 700 "$SSH_DIR"
    $SUDO chmod 600 "$AUTH"

    keys_filtered=$(cat | grep -E '^(ssh-(rsa|ed25519)|ecdsa-sha2-nistp(256|384|521))\s' || true)
    if [ -z "$keys_filtered" ]; then
        echo -e "${ERROR} 未检测到有效公钥"
        exit 1
    fi

    $SUDO sh -c "printf '\n# added by root_ssh_modifier %s (v%s)\n' '$(date -u +%FT%TZ)' '${VERSION}' >> '$AUTH'"
    echo "$keys_filtered" | $SUDO tee -a "$AUTH" >/dev/null

    tmp=$($SUDO mktemp)
    if [ -n "$SUDO" ]; then
        $SUDO sh -c "awk 'NF' '$AUTH' | sort -u > '$tmp' && mv '$tmp' '$AUTH' && chown root:root '$AUTH' && chmod 600 '$AUTH'"
    else
        awk 'NF' "$AUTH" | sort -u > "$tmp" && mv "$tmp" "$AUTH" && chown root:root "$AUTH" && chmod 600 "$AUTH"
    fi
    restorecon -R "$SSH_DIR" 2>/dev/null || true

    echo -e "${SUCCESS} 公钥已写入: $AUTH"
    set_sshd_option "PubkeyAuthentication" "yes"
}

add_key_literal_or_file() {
    local input="$1"
    if [ -f "$input" ]; then
        echo -e "${INFO} 从文件读取公钥: $input"
        cat "$input" | install_keys_to_root
    else
        echo -e "${INFO} 使用提供的公钥字串"
        printf '%s\n' "$input" | install_keys_to_root
    fi
}

fetch_github_keys() {
    local user="$1"
    need_cmd awk
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "https://github.com/${user}.keys"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO- "https://github.com/${user}.keys"
    else
        echo -e "${ERROR} 需要 curl 或 wget 拉取 GitHub 公钥" >&2
        return 1
    fi
}

add_keys_from_github() {
    local gh_user="$1"
    echo -e "${INFO} 正在从 GitHub 拉取公钥: ${gh_user}"
    keys="$(fetch_github_keys "$gh_user" || true)"
    if [ -z "$keys" ]; then
        echo -e "${ERROR} 拉取失败或该用户无公开密钥: ${gh_user}"
        exit 1
    fi
    printf '%s\n' "$keys" | install_keys_to_root
}

#---------------------- 原有功能 -----------------------
change_root_password() {
    local new_password="$1"
    if [ -z "$new_password" ]; then
        echo -e "${WARNING} 请输入新的root密码:"; read -s new_password; echo
        [ -z "$new_password" ] && { echo -e "${ERROR} 密码不能为空!"; exit 1; }
    fi
    echo -e "${INFO} 正在修改root密码..."
    echo "root:${new_password}" | $SUDO chpasswd || { echo -e "${ERROR} root密码修改失败!"; exit 1; }
    echo -e "${SUCCESS} root密码修改成功!"
}

change_ssh_port() {
    local new_port="$1"
    if [ -z "$new_port" ]; then
        echo -e "${WARNING} 请输入新的SSH端口 (默认: 2222):"; read new_port; new_port=${new_port:-2222}
    fi
    if ! [[ "$new_port" =~ ^[0-9]+$ ]] || [ "$new_port" -lt 1 ] || [ "$new_port" -gt 65535 ]; then
        echo -e "${ERROR} 无效的端口号: $new_port"; exit 1
    fi
    echo -e "${INFO} 正在修改SSH端口为 $new_port ..."
    backup_sshd_once
    if grep -q "^Port " /etc/ssh/sshd_config; then
        $SUDO sed -i "s/^Port .*/Port $new_port/" /etc/ssh/sshd_config
    else
        echo "Port $new_port" | $SUDO tee -a /etc/ssh/sshd_config >/dev/null
    fi
    grep -q "^Port $new_port" /etc/ssh/sshd_config || { echo -e "${ERROR} SSH端口修改失败!"; exit 1; }
    echo -e "${SUCCESS} SSH端口修改成功!"
    RESTART_SSHD=1
}

restart_ssh_service() {
    echo -e "${INFO} 正在重启SSH服务..."
    if command -v systemctl >/dev/null 2>&1; then
        # 优先检查Ubuntu系统的ssh服务
        if [[ "$OS" == "Ubuntu" ]]; then
            if systemctl is-active --quiet ssh; then
                $SUDO systemctl restart ssh
            elif systemctl is-active --quiet sshd; then
                $SUDO systemctl restart sshd
            else
                echo -e "${WARNING} 未找到活动的SSH服务，尝试启动..."
                $SUDO systemctl start ssh 2>/dev/null || $SUDO systemctl start sshd 2>/dev/null
            fi
        else
            # 非Ubuntu系统的处理逻辑
            if systemctl is-active --quiet sshd; then
                $SUDO systemctl restart sshd
            elif systemctl is-active --quiet ssh; then
                $SUDO systemctl restart ssh
            else
                echo -e "${WARNING} 未找到活动的SSH服务，尝试启动..."
                $SUDO systemctl start sshd 2>/dev/null || $SUDO systemctl start ssh 2>/dev/null
            fi
        fi
    elif command -v service >/dev/null 2>&1; then
        # Ubuntu系统优先尝试ssh服务
        if [[ "$OS" == "Ubuntu" ]]; then
            $SUDO service ssh restart 2>/dev/null || $SUDO service sshd restart 2>/dev/null
        else
            $SUDO service sshd restart 2>/dev/null || $SUDO service ssh restart 2>/dev/null
        fi
    elif [ -x /etc/init.d/ssh ]; then
        $SUDO /etc/init.d/ssh restart
    elif [ -x /etc/init.d/sshd ]; then
        $SUDO /etc/init.d/sshd restart
    else
        echo -e "${WARNING} 无法自动重启SSH服务，请手动重启"
        return 1
    fi
    [ $? -eq 0 ] && echo -e "${SUCCESS} SSH服务重启成功!" || { echo -e "${ERROR} SSH服务重启失败!"; return 1; }
}

check_ssh_status() {
    echo -e "${INFO} 检查SSH服务状态..."
    if command -v systemctl >/dev/null 2>&1; then
        # Ubuntu系统优先检查ssh服务
        if [[ "$OS" == "Ubuntu" ]]; then
            if systemctl is-active --quiet ssh; then
                echo -e "${SUCCESS} SSH服务正在运行 (ssh)"
            elif systemctl is-active --quiet sshd; then
                echo -e "${SUCCESS} SSH服务正在运行 (sshd)"
            else
                echo -e "${WARNING} SSH服务未运行"
            fi
        else
            # 非Ubuntu系统的处理逻辑
            if systemctl is-active --quiet sshd; then
                echo -e "${SUCCESS} SSH服务正在运行 (sshd)"
            elif systemctl is-active --quiet ssh; then
                echo -e "${SUCCESS} SSH服务正在运行 (ssh)"
            else
                echo -e "${WARNING} SSH服务未运行"
            fi
        fi
    else
        if pgrep sshd >/dev/null; then echo -e "${SUCCESS} SSH服务正在运行"
        else echo -e "${WARNING} SSH服务未运行"; fi
    fi
}

enable_password_login() {
    echo -e "${INFO} 正在启用密码登录..."
    set_sshd_option "PasswordAuthentication" "yes"
    set_sshd_option "PubkeyAuthentication" "yes"
    set_sshd_option "PermitRootLogin" "yes"
    set_sshd_option "ChallengeResponseAuthentication" "no"
    set_sshd_option "GSSAPIAuthentication" "no"
    echo -e "${SUCCESS} 已启用密码登录(并保留密钥登录)"
}

# 仅密钥登录
disable_password_login() {
    echo -e "${INFO} 正在禁用密码登录，仅允许密钥..."
    set_sshd_option "PasswordAuthentication" "no"
    # 仅允许root使用密钥登录
    set_sshd_option "PermitRootLogin" "prohibit-password"
    set_sshd_option "PubkeyAuthentication" "yes"
    echo -e "${SUCCESS} 已禁用密码登录"
}

show_current_config() {
    echo -e "${INFO} 当前SSH配置:"
    cp=$(grep "^Port " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
    echo -e "  端口: ${cp:-22}"
    pa=$(grep "^PasswordAuthentication " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
    echo -e "  密码认证: ${pa:-yes}"
    pk=$(grep "^PubkeyAuthentication " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
    echo -e "  公钥认证: ${pk:-yes}"
    rl=$(grep "^PermitRootLogin " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
    echo -e "  Root登录: ${rl:-yes}"
    cr=$(grep "^ChallengeResponseAuthentication " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
    echo -e "  挑战响应认证: ${cr:-no}"
}

#---------------------- 主流程 -----------------------
main() {
    local change_password=false change_port=false enable_password=false disable_password=false
    local install_key=false github_key=false
    local new_password="" new_port="" key_input="" gh_user=""

    while getopts "p:r:aekhDg:" OPT; do
        case $OPT in
            p) change_port=true; new_port="$OPTARG" ;;
            r) change_password=true; new_password="$OPTARG" ;;
            a) change_password=true; change_port=true ;;
            e) enable_password=true ;;
            k) install_key=true; key_input="$OPTARG" ;;
            g) github_key=true; gh_user="$OPTARG" ;;
            D) disable_password=true ;;
            h) USAGE; exit 0 ;;
            ?) USAGE; exit 1 ;;
        esac
    done

    [ $# -eq 0 ] && { USAGE; exit 1; }

    detect_system
    # Ubuntu系统特定检查
    check_ubuntu_packages
    show_current_config; echo

    # 修改账户/端口
    [ "$change_password" = true ] && { change_root_password "$new_password"; echo; }
    [ "$change_port" = true ] && { change_ssh_port "$new_port"; echo; }

    # 安装密钥
    if [ "$install_key" = true ]; then
        add_key_literal_or_file "$key_input"; echo
    fi
    if [ "$github_key" = true ]; then
        add_keys_from_github "$gh_user"; echo
    fi

    # 登录策略
    if [ "$disable_password" = true ]; then
        disable_password_login; echo
    elif [ "$enable_password" = true ]; then
        enable_password_login; echo
    fi

    # 重启并检查
    [ "$RESTART_SSHD" = 1 ] && { restart_ssh_service; echo; }
    check_ssh_status

    echo -e "${SUCCESS} 操作完成."
    if [ "$change_port" = true ] && [ -n "$new_port" ]; then
        echo -e "${WARNING} 使用新端口连接: ssh -p $new_port root@服务器IP"
    fi
}
main "$@"
