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



waitForText "$VM_LOGIN_TAG"

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




cat enablessh.txt >enablessh.local


#add ssh key twice, to avoid bugs.
echo "echo '$(base64 ~/.ssh/id_rsa.pub)' | openssl base64 -d >>~/.ssh/authorized_keys" >>enablessh.local
echo "" >>enablessh.local

echo "echo '$(cat ~/.ssh/id_rsa.pub)' >>~/.ssh/authorized_keys" >>enablessh.local
echo "" >>enablessh.local


echo >>enablessh.local
echo >>enablessh.local
echo "exit">>enablessh.local
echo >>enablessh.local


$vmsh inputFile $osname enablessh.local

ssh $osname sh <<EOF
echo 'StrictHostKeyChecking=accept-new' >.ssh/config

echo "Host host" >>.ssh/config
echo "     HostName  10.0.2.2" >>.ssh/config
echo "     User runner" >>.ssh/config

EOF


###############################################################


if [ -e "hooks/postBuild.sh" ]; then
  ssh $osname <"hooks/postBuild.sh"
fi


ssh $osname 'cat ~/.ssh/id_rsa.pub' >$osname-$VM_RELEASE-id_rsa.pub


ssh $osname  "$VM_SHUTDOWN_CMD"

sleep 5

###############################################################

$vmsh shutdownVM $osname


##############################################################




ova="$osname-$VM_RELEASE.ova"


echo "Exporting $ova"
$vmsh exportOVA $osname "$ova"

cp ~/.ssh/id_rsa  $osname-$VM_RELEASE-mac.id_rsa


ls -lah





