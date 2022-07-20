#some tasks run in the VM as soon as the vm is up






echo '=================== start ===='


gpart show ada0


gpart recover ada0


gpart resize -i 3  -a 4k ada0


growfs   -N  /dev/ada0p3


