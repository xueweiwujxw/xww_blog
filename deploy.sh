#!/usr/bin/expect

# never timeout
set timeout -1

# delete outdated pack
spawn ssh ubuntu@43.154.179.178
expect "*" {
    send "test -d ~/xww_blog && { cd ~/xww_blog; git pull --recurse-submodules; git submodule update --remote; } || { git clone https://github.com/xueweiwujxw/xww_blog.git --recurse-submodules; }\r"
    send "cd ~/xww_blog \r"
    send "hugo --minify --gc \r"
    send "sudo rm -rf /var/www/html/* \r"
    send "sudo cp -rvf ~/public/* /var/www/html/ \r"
    send "exit \r"
}
expect eof
