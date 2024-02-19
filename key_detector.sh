#!/bin/bash
# 颜色赋值
cyan='\e[96m'
red='\e[31m'
yellow='\e[33m'
green='\e[92m'
ES='\e[0m'
version="1.0"

err() {
    echo -e "\n$(echo -e "\e[41m错误!${ES}";) $@ \n" && exit 1
}

warn() {
    echo -e "\n$(echo -e "\e[43m警告!${ES}";) $@ \n"
}

ok() {
    echo -e "\n$(echo -e "\033[42m成功!${ES}";) $@ \n"
}

IM() {
# 自动获取网关地址
        echo -e "\n --------------------------- \n"
        warn "请手动输入网关IP：" 
		read IP
		while true; do
			if [[ $IP =~ ^192\.168\.[0-9]+\.1$ ]]; then
				break
			else
				read -p  "检测到IP格式错误，请手动输入：" IP
			fi
		done
			ok "网关地址为：$IP"
	# 提示用户输入12位的MAC地址
			echo -e "请输入${cyan}网关的MAC地址${NS}："
			read MAC
		while true; do
			MAC=${MAC^^}
			MAC=${MAC//:/}
			MAC=${MAC//-/}
		# 校验是否为12位
			if [[ ${#MAC} -ne 12 ]]; then
				warn "MAC地址格式错误！请重新输入："
				read MAC
			else
				break
			fi
		done
			ok "网关MAC地址为：$MAC"
}

# 检查是否为root用户
[[ $EUID != 0 ]] && err "当前非 ${yellow}ROOT用户${none}"

# 检查组件是否安装
check_installed() {
    which $1 &> /dev/null
    if [ $? -eq 0 ]; then
        ok "$1 已安装"
    else
        warn "$1 未安装，尝试安装"
        apt install $1
        if [ $? -eq 0 ]; then
			    echo -e "\n --------------------------- \n"
				ok "$1已安装!"
			else
				err "安装$1出错!"
		fi
    fi
}
check_installed curl
check_installed telnet
check_installed expect

warn "此脚本仅在${cyan}中国电信烽火HG6143D1${ES}测试通过！"

# 检查文件是否存在
if [ -f "IP_MAC_KEY" ]; then
# 读取文件内容并用awk分割
    content=$(awk -F "|" '{print $1,$2,$3}' "IP_MAC_KEY")
# 分别赋值给IP、MAC和KEY
    read IP MAC KEY <<<"$content"
# 显示结果
    echo -e "\n --------------------------- \n"
    echo -e "上一次使用的网关IP:${cyan} $IP ${ES}"
    echo -e "网关MAC:${cyan} $MAC ${ES}"
    echo -e "超级管理员密码:${cyan}  $KEY ${ES} \n --------------------------- \n"
    warn "是否沿用上一次的IP/MAC？（y/n）"
	 read CHOICE
		case ${CHOICE} in
		y|Y);;
		n|N)IM;;
		esac
else
	IM
fi


# 开启telnet
warn "正在尝试开启网关telnet"
RESULT=$(curl -s "http://${IP}:8080/cgi-bin/telnetenable.cgi?telnetenable=1&key=${MAC}")
# 将访问的结果进行校验
if [[ $RESULT == *"telnet"* ]]; then
    ok "telnet开启成功！"
else
    echo -e "\n --------------------------- \n"
    warn "telnet开启失败！请尝试手动开启"
    warn "请复制网址${red}http://$IP:8080/cgi-bin/telnetenable.cgi?telnetenable=1&key=$MAC${ES}到浏览器${cyan}访问${ES}手动开启网关telnet！\n\n(如果要关闭telnet请将${cyan}telnetenable=1${ES}该为${cyan}telnetenable=0${ES})\n\n如果网页没有出现${yellow}telnet开启成功${ES}可能有以下几点原因:\n\n1.IP地址错误\n2.MAC地址错误\n3.网关不支持\n"
read -p "如果开启成功请按y获取密码，按n退出脚本...." CHOICE
	case ${CHOICE} in
		y|Y);;
		n|N)exit 0;;
	esac
fi
warn "获取密码中！此过程需要20秒左右请稍作等待！"
# MAC地址的后六位作为参数
MAC6=$(echo $MAC | awk '{print substr($0, length($0)-5, length($0))}')

# 设置telnetadmin的密码
PASSWORD="FH-nE7jA%5m${MAC6}"

# 设置root的密码
ROOT_PASSWORD="Fh@${MAC6}"

# 启动telnet会话
# 将expect的输出重定向到文件中
expect <<EOF > telnet_hg6143d1.log
spawn telnet $IP
sleep 2

# 等待Login提示
expect {
    "Login:" {
        send "telnetadmin\r"
        sleep 1
    }
    timeout {
        send_user "连接网关失败！\n"
        exit
    }
}

# 输入密码
expect "Password:"
send "$PASSWORD\r"
sleep 1

# 检查是否成功登录
expect {
    "$" {
        send_user "成功登录。\n"
    }
    timeout {
        send_user "登录失败\n"
        exit
    }
}

# 获取root权限
send "su\r"
expect "Password:"
send "$ROOT_PASSWORD\r"
sleep 1

# 检查是否成功获取root权限
expect {
    "$" {
        send_user "成功获取root权限。\n"
    }
    timeout {
        send_user "获取root权限失败\n"
    }
}

# 执行命令
send "load_cli factory\r"
sleep 1
send "show admin_pwd\r"
sleep 1

# 获取密码
expect -re "Config\\\\factorydir# Success! admin_pwd=(.*)\s*\r"
set KEY $expect_out(1,string)
send_user "密码获取完毕！\n-----------------------\n"
send "exit\r"

# 结束会话
send "exit\r"
expect eof
EOF

# 使用grep从文件中提取密码
KEY=$(cat telnet_hg6143d1.log | grep -oP 'Success! admin_pwd=\K\S*')

if [[ -z "$KEY" ]]; then
	echo -e "\n --------------------------- \n"
	warn "管理密码获取失败！"
	echo -e "\n-----------下方为密码获取日志------------"
	cat telnet_hg6143d1.log
	echo -e "\n-----------------END------------------"
else
	echo -e "$IP|$MAC|$KEY" > IP_MAC_KEY
	echo -e "\n --------------------------- \n"
	ok "恭喜你，你已经获取了管理密码！密码是：$KEY "
fi
rm telnet_hg6143d1.log && exit 0
