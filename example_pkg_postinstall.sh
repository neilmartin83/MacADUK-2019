#!/bin/bash
# 2019-09-20 Added sleep to let things settle down before loading and tweaked to avoid having to kill the login window later on.
/bin/echo "Command: Image: "/Library/Application Support/UEL/branding/logo-prov.png"" >> /var/tmp/depnotify.log
/bin/echo "Command: MainTitle: Please wait a moment..."  >> /var/tmp/depnotify.log
/bin/echo "Command: MainText: " >> /var/tmp/depnotify.log
/bin/echo "Status: Please wait..." >> /var/tmp/depnotify.log
/usr/local/bin/authchanger -reset -preLogin NoMADLoginAD:Notify NoMADLoginAD:UserInput NoMADLoginAD:Notify
/bin/sleep 10
