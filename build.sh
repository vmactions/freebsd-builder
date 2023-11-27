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

vboxlink="${SEC_VBOX:-$VM_VBOX_LINK}"


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
  echo "Downloading $vboxlink"
  wget -O "$vmsh" "$vboxlink"
fi

chmod +x "$vmsh"



$vmsh startWeb $osname


$vmsh setup 

if ! $vmsh clearVM $osname; then
  echo "vm does not exists"
fi

if [ ! -e "$osname.qcow2.xz" ]; then
  echo "Downloading qcow2 from: $VM_VHD_LINK"
  wget -q -O $osname.qcow2.xz "$VM_VHD_LINK"

fi

if [ ! -e "$osname.qcow2" ]; then
  xz -d -T 0 --verbose  "$osname.qcow2.xz"
fi


$vmsh createVMFromVHD $osname $ostype $sshport






$vmsh startVM $osname

sleep 2


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



if [ ! -e ~/.ssh/id_rsa ] ; then 
  ssh-keygen -f  ~/.ssh/id_rsa -q -N "" 
fi

cat enablessh.txt >enablessh.local


#add ssh key twice, to avoid bugs.
echo "echo '$(base64  -w 0  ~/.ssh/id_rsa.pub)' | openssl base64 -d >>~/.ssh/authorized_keys" >>enablessh.local
echo "" >>enablessh.local

echo "echo '$(cat ~/.ssh/id_rsa.pub)' >>~/.ssh/authorized_keys" >>enablessh.local
echo "" >>enablessh.local


echo >>enablessh.local
echo >>enablessh.local
echo "exit">>enablessh.local
echo >>enablessh.local


$vmsh inputFile $osname enablessh.local


$vmsh addSSHHost  $osname


ssh $osname sh <<EOF
echo 'StrictHostKeyChecking=accept-new' >.ssh/config

echo "Host host" >>.ssh/config
echo "     HostName  192.168.122.1" >>.ssh/config
echo "     User runner" >>.ssh/config
echo "     ServerAliveInterval 1" >>.ssh/config

EOF


###############################################################


if [ -e "hooks/postBuild.sh" ]; then
  echo "hooks/postBuild.sh"
  cat "hooks/postBuild.sh"
  ssh $osname sh<"hooks/postBuild.sh"
fi


ssh $osname 'cat ~/.ssh/id_rsa.pub' >$osname-$VM_RELEASE-id_rsa.pub


if [ "$VM_PRE_INSTALL_PKGS" ]; then
  echo "$VM_INSTALL_CMD $VM_PRE_INSTALL_PKGS"
  ssh $osname sh <<<"$VM_INSTALL_CMD $VM_PRE_INSTALL_PKGS"
fi

ssh $osname  "$VM_SHUTDOWN_CMD"

sleep 5

###############################################################

$vmsh shutdownVM $osname

sleep 30

##############################################################




ova="$osname-$VM_RELEASE.qcow2"


echo "Exporting $ova"
$vmsh exportOVA $osname "$ova"

cp ~/.ssh/id_rsa  $osname-$VM_RELEASE-host.id_rsa


ls -lah


##############################################################

echo "Checking the packages: $VM_RSYNC_PKG $VM_SSHFS_PKG"

if [ -z "$VM_RSYNC_PKG$VM_SSHFS_PKG" ]; then
  echo "skip"
else
  $vmsh startVM $osname
  sleep 2
  waitForText "$VM_LOGIN_TAG"

  sleep 2

  ssh $osname sh <<<"$VM_INSTALL_CMD $VM_RSYNC_PKG $VM_SSHFS_PKG"
fi


