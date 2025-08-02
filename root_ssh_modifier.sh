#!/usr/bin/env bash
#=============================================================
# Root Password and SSH Port Modifier
# Description: One-click script to modify root password and SSH port
# Version: 1.0
# Author: Assistant
#=============================================================

VERSION=1.0
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

# 检测系统类型
detect_system() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$NAME
        VER=$VERSION_ID
    elif type lsb_release >/dev/null 2>&1; then
        OS=$(lsb_release -si)
        VER=$(lsb_release -sr)
    elif [ -f /etc/lsb-release ]; then
        . /etc/lsb-release
        OS=$DISTRIB_ID
        VER=$DISTRIB_RELEASE
    elif [ -f /etc/debian_version ]; then
        OS=Debian
        VER=$(cat /etc/debian_version)
    elif [ -f /etc/SuSe-release ]; then
        OS=SuSE
    elif [ -f /etc/redhat-release ]; then
        OS=RedHat
    else
        OS=$(uname -s)
        VER=$(uname -r)
    fi
    echo -e "${INFO} 检测到系统: ${OS} ${VER}"
}

# 显示使用说明
USAGE() {
    echo "
Root密码和SSH端口修改器 $VERSION

用法:
  bash root_ssh_modifier.sh [选项]

选项:
  -p <端口号>    修改SSH端口 (默认: 22)
  -r <新密码>    修改root密码
  -a             同时修改密码和端口
  -e             启用密码登录 (当服务器只允许密钥登录时)
  -h             显示此帮助信息

示例:
  bash root_ssh_modifier.sh -p 2222                    # 只修改SSH端口为2222
  bash root_ssh_modifier.sh -r 'newpassword123'        # 只修改root密码
  bash root_ssh_modifier.sh -a -p 2222 -r 'newpass'    # 同时修改端口和密码
  bash root_ssh_modifier.sh -e                         # 启用密码登录
  bash root_ssh_modifier.sh -a -p 2222 -r 'pass' -e    # 修改端口、密码并启用密码登录
"
}

# 修改root密码
change_root_password() {
    local new_password="$1"
    
    if [ -z "$new_password" ]; then
        echo -e "${WARNING} 请输入新的root密码:"
        read -s new_password
        echo
        if [ -z "$new_password" ]; then
            echo -e "${ERROR} 密码不能为空!"
            exit 1
        fi
    fi
    
    echo -e "${INFO} 正在修改root密码..."
    
    # 使用chpasswd命令修改密码
    echo "root:${new_password}" | $SUDO chpasswd
    
    if [ $? -eq 0 ]; then
        echo -e "${SUCCESS} root密码修改成功!"
    else
        echo -e "${ERROR} root密码修改失败!"
        exit 1
    fi
}

# 修改SSH端口
change_ssh_port() {
    local new_port="$1"
    
    if [ -z "$new_port" ]; then
        echo -e "${WARNING} 请输入新的SSH端口 (默认: 2222):"
        read new_port
        new_port=${new_port:-2222}
    fi
    
    # 验证端口号
    if ! [[ "$new_port" =~ ^[0-9]+$ ]] || [ "$new_port" -lt 1 ] || [ "$new_port" -gt 65535 ]; then
        echo -e "${ERROR} 无效的端口号: $new_port (端口范围: 1-65535)"
        exit 1
    fi
    
    echo -e "${INFO} 正在修改SSH端口为 $new_port ..."
    
    # 备份原配置文件
    if [ -f /etc/ssh/sshd_config ]; then
        $SUDO cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup.$(date +%Y%m%d_%H%M%S)
        echo -e "${INFO} 已备份原配置文件"
    fi
    
    # 修改SSH配置文件
    if grep -q "^Port " /etc/ssh/sshd_config; then
        # 如果已有Port配置，则替换
        $SUDO sed -i "s/^Port .*/Port $new_port/" /etc/ssh/sshd_config
    else
        # 如果没有Port配置，则添加
        echo "Port $new_port" | $SUDO tee -a /etc/ssh/sshd_config > /dev/null
    fi
    
    # 验证修改是否成功
    if grep -q "^Port $new_port" /etc/ssh/sshd_config; then
        echo -e "${SUCCESS} SSH端口修改成功!"
        RESTART_SSHD=1
    else
        echo -e "${ERROR} SSH端口修改失败!"
        exit 1
    fi
}

# 重启SSH服务
restart_ssh_service() {
    echo -e "${INFO} 正在重启SSH服务..."
    
    # 检测系统类型并重启相应的服务
    if command -v systemctl >/dev/null 2>&1; then
        # 使用systemctl (新版本系统)
        if systemctl is-active --quiet sshd; then
            $SUDO systemctl restart sshd
        elif systemctl is-active --quiet ssh; then
            $SUDO systemctl restart ssh
        else
            echo -e "${WARNING} 未找到活动的SSH服务，尝试启动..."
            $SUDO systemctl start sshd 2>/dev/null || $SUDO systemctl start ssh 2>/dev/null
        fi
    elif command -v service >/dev/null 2>&1; then
        # 使用service命令 (老版本系统)
        $SUDO service ssh restart 2>/dev/null || $SUDO service sshd restart 2>/dev/null
    elif command -v /etc/init.d/ssh >/dev/null 2>&1; then
        # 直接使用init脚本
        $SUDO /etc/init.d/ssh restart
    else
        echo -e "${WARNING} 无法自动重启SSH服务，请手动重启"
        echo -e "${INFO} 可以使用以下命令之一:"
        echo -e "  systemctl restart sshd"
        echo -e "  systemctl restart ssh"
        echo -e "  service ssh restart"
        echo -e "  /etc/init.d/ssh restart"
        return 1
    fi
    
    if [ $? -eq 0 ]; then
        echo -e "${SUCCESS} SSH服务重启成功!"
    else
        echo -e "${ERROR} SSH服务重启失败!"
        return 1
    fi
}

# 检查SSH服务状态
check_ssh_status() {
    echo -e "${INFO} 检查SSH服务状态..."
    
    if command -v systemctl >/dev/null 2>&1; then
        if systemctl is-active --quiet sshd; then
            echo -e "${SUCCESS} SSH服务正在运行 (sshd)"
        elif systemctl is-active --quiet ssh; then
            echo -e "${SUCCESS} SSH服务正在运行 (ssh)"
        else
            echo -e "${WARNING} SSH服务未运行"
        fi
    else
        if pgrep sshd >/dev/null; then
            echo -e "${SUCCESS} SSH服务正在运行"
        else
            echo -e "${WARNING} SSH服务未运行"
        fi
    fi
}

# 启用密码登录
enable_password_login() {
    echo -e "${INFO} 正在启用密码登录..."
    
    # 备份原配置文件
    if [ -f /etc/ssh/sshd_config ]; then
        $SUDO cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup.$(date +%Y%m%d_%H%M%S)
        echo -e "${INFO} 已备份原配置文件"
    fi
    
    # 修改SSH配置文件以启用密码登录
    local config_changes=false
    
    # 启用密码认证
    if grep -q "^PasswordAuthentication " /etc/ssh/sshd_config; then
        $SUDO sed -i "s/^PasswordAuthentication .*/PasswordAuthentication yes/" /etc/ssh/sshd_config
        config_changes=true
    else
        echo "PasswordAuthentication yes" | $SUDO tee -a /etc/ssh/sshd_config > /dev/null
        config_changes=true
    fi
    
    # 启用公钥认证（保持兼容性）
    if grep -q "^PubkeyAuthentication " /etc/ssh/sshd_config; then
        $SUDO sed -i "s/^PubkeyAuthentication .*/PubkeyAuthentication yes/" /etc/ssh/sshd_config
        config_changes=true
    else
        echo "PubkeyAuthentication yes" | $SUDO tee -a /etc/ssh/sshd_config > /dev/null
        config_changes=true
    fi
    
    # 允许root登录（如果需要）
    if grep -q "^PermitRootLogin " /etc/ssh/sshd_config; then
        $SUDO sed -i "s/^PermitRootLogin .*/PermitRootLogin yes/" /etc/ssh/sshd_config
        config_changes=true
    else
        echo "PermitRootLogin yes" | $SUDO tee -a /etc/ssh/sshd_config > /dev/null
        config_changes=true
    fi
    
    # 禁用挑战响应认证（简化配置）
    if grep -q "^ChallengeResponseAuthentication " /etc/ssh/sshd_config; then
        $SUDO sed -i "s/^ChallengeResponseAuthentication .*/ChallengeResponseAuthentication no/" /etc/ssh/sshd_config
        config_changes=true
    else
        echo "ChallengeResponseAuthentication no" | $SUDO tee -a /etc/ssh/sshd_config > /dev/null
        config_changes=true
    fi
    
    # 禁用GSSAPI认证（简化配置）
    if grep -q "^GSSAPIAuthentication " /etc/ssh/sshd_config; then
        $SUDO sed -i "s/^GSSAPIAuthentication .*/GSSAPIAuthentication no/" /etc/ssh/sshd_config
        config_changes=true
    else
        echo "GSSAPIAuthentication no" | $SUDO tee -a /etc/ssh/sshd_config > /dev/null
        config_changes=true
    fi
    
    if [ "$config_changes" = true ]; then
        echo -e "${SUCCESS} SSH密码登录配置修改成功!"
        echo -e "${INFO} 已启用以下设置:"
        echo -e "  - PasswordAuthentication yes"
        echo -e "  - PubkeyAuthentication yes"
        echo -e "  - PermitRootLogin yes"
        echo -e "  - ChallengeResponseAuthentication no"
        echo -e "  - GSSAPIAuthentication no"
        RESTART_SSHD=1
    else
        echo -e "${WARNING} 未发现需要修改的配置"
    fi
}

# 显示当前SSH配置
show_current_config() {
    echo -e "${INFO} 当前SSH配置:"
    
    # 显示当前端口
    current_port=$(grep "^Port " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
    if [ -n "$current_port" ]; then
        echo -e "  端口: $current_port"
    else
        echo -e "  端口: 22 (默认)"
    fi
    
    # 显示密码认证设置
    password_auth=$(grep "^PasswordAuthentication " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
    if [ -n "$password_auth" ]; then
        echo -e "  密码认证: $password_auth"
    else
        echo -e "  密码认证: yes (默认)"
    fi
    
    # 显示公钥认证设置
    pubkey_auth=$(grep "^PubkeyAuthentication " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
    if [ -n "$pubkey_auth" ]; then
        echo -e "  公钥认证: $pubkey_auth"
    else
        echo -e "  公钥认证: yes (默认)"
    fi
    
    # 显示root登录设置
    root_login=$(grep "^PermitRootLogin " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
    if [ -n "$root_login" ]; then
        echo -e "  Root登录: $root_login"
    else
        echo -e "  Root登录: yes (默认)"
    fi
    
    # 显示挑战响应认证设置
    challenge_auth=$(grep "^ChallengeResponseAuthentication " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
    if [ -n "$challenge_auth" ]; then
        echo -e "  挑战响应认证: $challenge_auth"
    else
        echo -e "  挑战响应认证: no (默认)"
    fi
}

# 主函数
main() {
    local change_password=false
    local change_port=false
    local enable_password=false
    local new_password=""
    local new_port=""
    
    # 检查参数
    while getopts "p:r:aeh" OPT; do
        case $OPT in
            p)
                change_port=true
                new_port="$OPTARG"
                ;;
            r)
                change_password=true
                new_password="$OPTARG"
                ;;
            a)
                change_password=true
                change_port=true
                ;;
            e)
                enable_password=true
                ;;
            h)
                USAGE
                exit 0
                ;;
            ?)
                USAGE
                exit 1
                ;;
        esac
    done
    
    # 如果没有参数，显示使用说明
    if [ $# -eq 0 ]; then
        USAGE
        exit 1
    fi
    
    # 检测系统
    detect_system
    
    # 显示当前配置
    show_current_config
    echo
    
    # 执行修改操作
    if [ "$change_password" = true ]; then
        change_root_password "$new_password"
        echo
    fi
    
    if [ "$change_port" = true ]; then
        change_ssh_port "$new_port"
        echo
    fi
    
    if [ "$enable_password" = true ]; then
        enable_password_login
        echo
    fi
    
    # 重启SSH服务
    if [ "$RESTART_SSHD" = 1 ]; then
        restart_ssh_service
        echo
    fi
    
    # 最终检查
    check_ssh_status
    
    echo -e "${SUCCESS} 所有操作完成!"
    
    if [ "$change_port" = true ] && [ -n "$new_port" ]; then
        echo -e "${INFO} 新的SSH端口: $new_port"
        echo -e "${WARNING} 请使用新端口连接SSH: ssh -p $new_port root@服务器IP"
    fi
    
    if [ "$enable_password" = true ]; then
        echo -e "${INFO} 密码登录已启用!"
        echo -e "${WARNING} 现在可以使用密码登录SSH"
        if [ "$change_password" = true ]; then
            echo -e "${INFO} 请使用新设置的root密码登录"
        fi
    fi
}

# 执行主函数
main "$@" 