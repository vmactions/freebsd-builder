#some tasks run in the VM as soon as the vm is up






echo '=================== start ===='





service ntpd enable

service ntpd start




#enable autologin with root in the console

sed -E -i '' 's|ttyv0[[:space:]]+"/usr/libexec/getty Pc"|ttyv0	  "/usr/libexec/getty autologin"|' /etc/ttys




