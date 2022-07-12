#!/usr/bin/env bash



set -e


_conf="$1"

if [ -z "$_conf" ] ; then
  echo "Please give the conf file"
  exit 1
fi


. "$_conf"


##############################################################
osname="$VM_OS_NAME"
ostype="$VM_OS_TYPE"
sshport=$VM_SSH_PORT


opts="$VM_OPTS"

vboxlink="$VM_VBOX_LINK"


vmsh="$VM_VBOX"


export VM_OS_NAME



##############################################################


waitForText() {
  _text="$1"
  $vmsh waitForText $osname "$_text"
}

#keys splitted by ;
#eg:  enter
#eg:  down; enter
#eg:  down; up; tab; enter


inputKeys() {
  $vmsh input $osname "$1"
}



if [ ! -e "$vmsh" ] ; then
  wget -O "$vmsh" "$vboxlink"
fi

chmod +x "$vmsh"


$vmsh addSSHHost  $osname $sshport



$vmsh setup 

if ! $vmsh clearVM $osname; then
  echo "vm does not exists"
fi

if [ ! -e "$osname.vhd.xz" ]; then
  echo "Downloading vhd from: $VM_VHD_LINK"
  wget -q -O $osname.vhd.xz "$VM_VHD_LINK"

fi

if [ ! -e "$osname.vhd" ]; then
  xz -d -T 0 --verbose  "$osname.vhd.xz"
fi


$vmsh createVMFromVHD $osname $ostype $sshport



$vmsh startWeb $osname



$vmsh startCF


_sleep=20
echo "Sleep $_sleep seconds, please open the link in your browser."
sleep $_sleep

$vmsh startVM $osname

sleep 2





#$vmsh  processOpts  $osname  "$opts"


#$vmsh shutdownVM $osname


#$vmsh detachISO $osname

#$vmsh startVM $osname



###############################################

waitForText "Welcome to FreeBSD"

$vmsh enter  $osname


waitForText "FreeBSD/amd64 (freebsd) (ttyv"

sleep 3

$vmsh enter  $osname
sleep 1

$vmsh enter  $osname
sleep 1

$vmsh enter  $osname
sleep 1

$vmsh enter  $osname
sleep 1

inputKeys "string root ; enter ; enter"


echo "

gpart show ada0
gpart recover ada0

gpart resize -i 3  -a 4k ada0

growfs   -N  /dev/ada0p3

echo 'sshd_enable=\"YES\"' >>/etc/rc.conf

service sshd start

echo '' >>  /etc/ssh/sshd_config

echo 'PermitRootLogin yes' >>  /etc/ssh/sshd_config

echo 'PermitEmptyPasswords yes' >> /etc/ssh/sshd_config

echo 'PasswordAuthentication yes'  >> /etc/ssh/sshd_config

echo 'AcceptEnv   *'  >> /etc/ssh/sshd_config

ssh-keygen -t rsa -f ~/.ssh/id_rsa -q -N ""


service sshd restart

passwd





" >enablessh.txt





echo "echo '$(base64 ~/.ssh/id_rsa.pub)' | openssl base64 -d >>~/.ssh/authorized_keys" >>enablessh.txt


echo >>enablessh.txt
echo >>enablessh.txt
echo "exit">>enablessh.txt
echo >>enablessh.txt




$vmsh inputFile $osname enablessh.txt

###############################################################


ssh $osname 'cat ~/.ssh/id_rsa.pub' >id_rsa.pub

ssh $osname  "/sbin/shutdown -p now"

sleep 5

###############################################################

$vmsh shutdownVM $osname


##############################################################




ova="$VM_OVA_NAME.ova"

$vmsh exportOVA $osname "$ova"

cp ~/.ssh/id_rsa  mac.id_rsa


7z a $ova.7z  id_rsa.pub $ova  mac.id_rsa



