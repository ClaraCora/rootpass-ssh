# Root SSH Modifier

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Shell Script](https://img.shields.io/badge/Shell%20Script-Bash-blue.svg)](https://www.gnu.org/software/bash/)
[![Platform](https://img.shields.io/badge/Platform-Linux%20%7C%20Unix-lightgrey.svg)](https://www.linux.org/)

一个功能强大的一键修改root密码和SSH端口的脚本，适用于多个Linux发行版。

## 🌟 特性

- 🔐 **安全修改root密码** - 使用`chpasswd`命令安全地修改密码
- 🔌 **修改SSH端口** - 自动备份配置文件并修改端口设置
- 🔑 **启用密码登录** - 自动配置SSH允许密码认证（适用于只允许密钥登录的服务器）
- 🛡️ **自动备份** - 修改前自动备份SSH配置文件
- 🔄 **自动重启服务** - 支持多种服务管理方式（systemctl/service/init.d）
- 🖥️ **多系统兼容** - 支持Debian、Ubuntu、CentOS等多个发行版
- 📊 **状态检查** - 显示当前配置和服务状态
- ⚠️ **错误处理** - 完善的错误检查和提示
- 🎨 **彩色输出** - 清晰的状态提示

## 🚀 快速开始

### 安装

```bash
# 下载脚本
wget https://raw.githubusercontent.com/ClaraCora/rootpass-ssh/main/root_ssh_modifier.sh

# 添加执行权限
chmod +x root_ssh_modifier.sh
```

### 基本用法

```bash
# 只修改SSH端口
sudo ./root_ssh_modifier.sh -p 2222

# 只修改root密码
sudo ./root_ssh_modifier.sh -r 'newpassword123'

# 同时修改端口和密码
sudo ./root_ssh_modifier.sh -a -p 2222 -r 'newpassword123'

# 显示帮助信息
./root_ssh_modifier.sh -h
```

## 📖 详细用法

### 参数说明

| 参数 | 说明 | 示例 |
|------|------|------|
| `-p <端口号>` | 修改SSH端口 (范围: 1-65535) | `-p 2222` |
| `-r <新密码>` | 修改root密码 | `-r 'MyPassword123!'` |
| `-a` | 同时修改密码和端口 | `-a -p 2222 -r 'pass'` |
| `-e` | 启用密码登录 | `-e` |
| `-h` | 显示帮助信息 | `-h` |

### 使用示例

#### 1. 只修改SSH端口
```bash
sudo ./root_ssh_modifier.sh -p 2222
```

#### 2. 只修改root密码
```bash
sudo ./root_ssh_modifier.sh -r 'MySecurePassword123!'
```

#### 3. 同时修改端口和密码
```bash
sudo ./root_ssh_modifier.sh -a -p 2222 -r 'MySecurePassword123!'
```

#### 4. 交互式输入密码
```bash
sudo ./root_ssh_modifier.sh -r
# 脚本会提示输入新密码
```

#### 5. 启用密码登录（适用于只允许密钥登录的服务器）
```bash
sudo ./root_ssh_modifier.sh -e
```

#### 6. 同时修改端口、密码并启用密码登录
```bash
sudo ./root_ssh_modifier.sh -a -p 2222 -r 'MySecurePassword123!' -e
```

## 🖥️ 支持的系统

- ✅ **Debian** (所有版本)
- ✅ **Ubuntu** (所有版本)
- ✅ **CentOS/RHEL** (所有版本)
- ✅ **Fedora**
- ✅ **openSUSE**
- ✅ **其他基于systemd或init的Linux发行版**

## 🔧 服务管理支持

脚本自动检测并使用最适合的服务管理方式：

- **systemctl** (新版本系统)
- **service** (老版本系统)
- **/etc/init.d/** (传统init系统)

## 🔑 密码登录功能

### 适用场景

当服务器配置为只允许密钥登录时，可以使用 `-e` 参数启用密码登录：

```bash
sudo ./root_ssh_modifier.sh -e
```

### 自动配置的SSH设置

脚本会自动修改以下SSH配置：

- **PasswordAuthentication yes** - 启用密码认证
- **PubkeyAuthentication yes** - 保持公钥认证（兼容性）
- **PermitRootLogin yes** - 允许root用户登录
- **ChallengeResponseAuthentication no** - 禁用挑战响应认证
- **GSSAPIAuthentication no** - 禁用GSSAPI认证

### 使用建议

1. **安全考虑** - 启用密码登录后，请使用强密码
2. **防火墙设置** - 确保防火墙允许SSH端口
3. **定期检查** - 定期检查SSH日志确保安全
4. **备份配置** - 脚本会自动备份原配置文件

## 🛡️ 安全特性

### 自动备份
- 修改前自动备份SSH配置文件
- 备份文件名包含时间戳
- 示例：`sshd_config.backup.20231201_143022`

### 密码安全
- 密码输入时隐藏字符
- 验证密码不为空
- 建议使用强密码

### 配置验证
- 验证端口号范围 (1-65535)
- 验证配置文件修改是否成功
- 检查SSH服务状态

## ⚠️ 安全注意事项

1. **备份重要数据** - 脚本会自动备份SSH配置文件，但建议在修改前手动备份重要数据
2. **测试连接** - 修改端口后，请先测试新端口连接是否正常，再关闭旧端口
3. **强密码** - 建议使用包含大小写字母、数字和特殊字符的强密码
4. **防火墙** - 修改端口后，记得更新防火墙规则

## 🔧 故障排除

### 常见问题

#### 1. 权限不足
```bash
# 确保使用sudo运行
sudo ./root_ssh_modifier.sh -p 2222
```

#### 2. SSH服务重启失败
```bash
# 手动重启SSH服务
sudo systemctl restart sshd
# 或
sudo service ssh restart
```

#### 3. 无法连接SSH
- 检查防火墙是否允许新端口
- 确认SSH服务正在运行
- 检查配置文件语法是否正确

### 恢复备份

如果出现问题，可以恢复备份的配置文件：

```bash
# 查看备份文件
ls -la /etc/ssh/sshd_config.backup.*

# 恢复备份
sudo cp /etc/ssh/sshd_config.backup.20231201_143022 /etc/ssh/sshd_config
sudo systemctl restart sshd
```

## 📋 完整使用示例

```bash
# 步骤1: 下载并设置权限
wget https://raw.githubusercontent.com/ClaraCora/rootpass-ssh/main/root_ssh_modifier.sh
chmod +x root_ssh_modifier.sh

# 步骤2: 查看帮助
./root_ssh_modifier.sh -h

# 步骤3: 修改端口和密码，并启用密码登录
sudo ./root_ssh_modifier.sh -a -p 2222 -r 'MySecurePassword123!' -e

# 步骤4: 测试新配置
ssh -p 2222 root@服务器IP

# 步骤5: 更新防火墙 (如果需要)
sudo ufw allow 2222/tcp
sudo ufw reload
```

## 📊 脚本特性

- ✅ 自动检测系统类型
- ✅ 自动备份配置文件
- ✅ 支持多种服务管理方式
- ✅ 完善的错误处理
- ✅ 彩色输出提示
- ✅ 参数验证
- ✅ 状态检查

## 🤝 贡献

欢迎提交Issue和Pull Request！

### 贡献指南

1. Fork 这个仓库
2. 创建你的特性分支 (`git checkout -b feature/AmazingFeature`)
3. 提交你的更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 打开一个 Pull Request

## 📄 许可证

本项目采用 MIT 许可证 - 查看 [LICENSE](LICENSE) 文件了解详情。

## ⚠️ 免责声明

此脚本仅供学习和合法使用。使用者需要对自己的操作负责，建议在测试环境中先验证脚本功能。

## 📞 支持

如果你遇到问题或有建议，请：

1. 查看 [Issues](../../issues) 页面
2. 创建新的 Issue
3. 或者联系维护者

---

**⭐ 如果这个项目对你有帮助，请给它一个星标！** 