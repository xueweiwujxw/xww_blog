#!/usr/bin/expect

# never timeout
set timeout -1

spawn rm -rf public
spawn hugo
expect eof

# delete outdated pack
spawn ssh ubuntu@wlanxww.com
expect "*" {
    send "rm -rf ~/public \r"
    send "exit \r"
}
expect eof

# upload upgraded pack
spawn scp -r ./public ubuntu@wlanxww.com:~/
expect eof

# sync to nginx
spawn ssh ubuntu@wlanxww.com
expect "*" {
    send "sudo rm -rf /var/www/html/* \r"
    send "sudo cp -rvf ~/public/* /var/www/html/ \r"
    send "exit \r"
}
expect eof