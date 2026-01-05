#!/usr/bin/env bash

set -ex


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
export VM_RELEASE
export VM_OCR
export VM_DISK
export VM_ARCH
export VM_CPU
export VM_USE_CONSOLE_BUILD
export VM_USE_SSHROOT_BUILD_SSH
export VM_NO_VNC_BUILD
export VM_USE_NC_ENABLE_SSH
export VM_USE_TELNET_ENABLE_SSH
export VM_USE_BASH_ENABLE_SSH
export VM_NIC


##############################################################


waitForText() {
  _text="$1"
  _sec="$2"
  $vmsh waitForText $osname "$_text" "$_sec"
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



$vmsh startWeb $osname "needOCR"


$vmsh setup "needOCR"

if ! $vmsh clearVM $osname; then
  echo "vm does not exists"
fi


if [ "$VM_ISO_LINK" ]; then
  #start from iso, install to the vir disk

  $vmsh createVM  "$VM_ISO_LINK" "$osname" "$ostype" "$sshport" "$VM_PRE_DISK_LINK"

  sleep 2

  $vmsh openConsole "$osname"

  if [ -e "hooks/installOpts.sh" ]; then
    echo "hooks/installOpts.sh"
    cat "hooks/installOpts.sh"
    . "hooks/installOpts.sh"
  else
    $vmsh  processOpts  $osname  "$opts"
  
    echo "sleep 60 seconds. just wait"
    sleep 60
  
    if $vmsh isRunning $osname; then
      if ! $vmsh shutdownVM $osname; then
        echo "shutdown error"
      fi
      if ! $vmsh destroyVM $osname; then
        echo "destroyVM error"
      fi
    fi
  fi

  while $vmsh isRunning $osname; do
    sleep 20
  done

  $vmsh closeConsole "$osname"


  if [[ "$VM_ISO_LINK" == *"img" ]]; then
    $vmsh detachIMG "$osname"
  fi

elif [ "$VM_VHD_LINK" ]; then
  #if the vm disk is already provided FreeBSD, just import it.
  if [ ! -e "$osname.qcow2" ]; then
    if [[ "$VM_VHD_LINK" == *"img.gz" ]]; then
      _img="$osname.img"
      if [ ! -e "$_img" ]; then
        rm -f "$_img.gz"
        $vmsh download "$VM_VHD_LINK" "$_img.gz"
        gunzip -c "$_img.gz" > "$_img"
      fi
      qemu-img convert -f raw -O qcow2 -o preallocation=off "$_img" "$osname.qcow2"
    elif [[ "$VM_VHD_LINK" == *"img.zst" ]]; then
      _img="$osname.img"
      if [ ! -e "$_img" ]; then
        rm -f "$_img.zst"
        $vmsh download "$VM_VHD_LINK" "$_img.zst"
        zstd -f -d "$_img.zst" -o "$_img"
      fi
      qemu-img convert -f raw -O qcow2 -o preallocation=off "$_img" "$osname.qcow2"
    else
      if [ ! -e "$osname.qcow2.xz" ]; then
        $vmsh download "$VM_VHD_LINK" $osname.qcow2.xz
      fi
      xz -d -T 0 --verbose  "$osname.qcow2.xz"
    fi

  fi

  $vmsh createVMFromVHD $osname $ostype $sshport

  sleep 5

else
  echo "no VM_ISO_LINK or VM_VHD_LINK, can not build."
  exit 1
fi


echo "VM image size immediately after install:"
ls -lh


start_and_wait() {
  $vmsh startVM $osname
  sleep 2
  $vmsh openConsole "$osname"

  if [ -e "hooks/waitForLoginTag.sh" ]; then
    echo "hooks/waitForLoginTag.sh"
    cat "hooks/waitForLoginTag.sh"
    . "hooks/waitForLoginTag.sh"
  else
    waitForText "$VM_LOGIN_TAG"
  fi

  sleep 3
}

shutdown_and_wait() {
  if ! ssh -o ConnectTimeout=5 -o ServerAliveInterval=2 $osname  "$VM_SHUTDOWN_CMD"; then
    echo "shutdown $?, haiku? but we just ignore it."
  fi

  sleep 30

  if $vmsh isRunning $osname; then
    if ! $vmsh shutdownVM $osname; then
      echo "shutdown error"
    fi
  fi

  while $vmsh isRunning $osname; do
    sleep 5
  done

  $vmsh closeConsole "$osname"

}

restart_and_wait() {
  shutdown_and_wait
  start_and_wait
}

###############################################


#start the installed vm, and initialize the ssh access:


if [ -z "$VM_NO_VNC_BUILD" ]; then
  #switch back to use vnc
  export VM_USE_CONSOLE_BUILD=""
fi

start_and_wait


if [ ! -e ~/.ssh/id_rsa ] ; then 
  ssh-keygen -f  ~/.ssh/id_rsa -q -N "" 
fi

rm -f enablessh.local
cat enablessh.txt >enablessh.local


echo "echo '$(cat ~/.ssh/id_rsa.pub)' >>~/.ssh/authorized_keys" >>enablessh.local
echo "" >>enablessh.local
echo "" >>enablessh.local
echo "" >>enablessh.local

#add ssh key twice, to avoid bugs.
echo "echo '$(base64 -w 0 ~/.ssh/id_rsa.pub)' | openssl base64 -d >>~/.ssh/authorized_keys" >>enablessh.local
echo "" >>enablessh.local
echo "" >>enablessh.local


echo >>enablessh.local
echo "chmod 600 ~/.ssh/authorized_keys">>enablessh.local

echo "">>enablessh.local
echo >>enablessh.local


cat enablessh.local

if [ -e "hooks/enablessh.sh" ]; then
    cat "hooks/enablessh.sh"
    . "hooks/enablessh.sh"
elif [ "$VM_USE_SSHROOT_BUILD_SSH" ]; then
  vmip=$($vmsh getVMIP $osname)
  sshpass -p "$VM_ROOT_PASSWORD" ssh -o StrictHostKeyChecking=no -tt  root@$vmip TERM=xterm <enablessh.local
  #sleep for the sshd server to restart
  sleep 10
  inputKeys "enter"
  sleep 2
  inputKeys "enter"
  sleep 2
  echo "check ssh access:"
  ssh -vv root@$vmip pwd
  echo "ssh OK"
else
  echo "login as root at console."
  inputKeys "enter"
  inputKeys "enter"
  sleep 20
  inputKeys "enter"
  inputKeys "enter"
  inputKeys "string root; enter; sleep 5;"
  if [ "$VM_ROOT_PASSWORD" ]; then
    inputKeys "string $VM_ROOT_PASSWORD ; enter"
    sleep 10
  fi
  inputKeys "enter"
  sleep 20
  inputKeys "enter"

  $vmsh screenText $osname

  if [ -e "hooks/enableNetwork.sh" ]; then
    echo "hooks/enableNetwork.sh"
    cat "hooks/enableNetwork.sh"
    echo "To enabled network, we have to input throw stdin"
    $vmsh inputFileStdIn "$osname" hooks/enableNetwork.sh
    $vmsh screenText $osname
    sleep 60
  fi

  if [ "$VM_USE_NC_ENABLE_SSH" ]; then
    #for openbsd 7.7/7.8
    $vmsh inputFileNC $osname enablessh.local
  elif [ "$VM_USE_BASH_ENABLE_SSH" ]; then
    #for openIndiana
    $vmsh inputFileBash $osname enablessh.local
  else
    $vmsh inputFile $osname enablessh.local
  fi
  sleep 60
  $vmsh screenText $osname
  #sleep for the sshd server to restart
  sleep 10
  inputKeys "enter"
  sleep 2
  inputKeys "enter"
  sleep 2
fi


###############################################################

$vmsh addSSHHost  $osname

echo "Sleep for the sshd to restart"
sleep 10

_retry=0
_restarted=""
while ! timeout 2 ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR $osname exit >/dev/null 2>&1; do
  echo "ssh is not ready, just wait."
  sleep 10
  _retry=$(($_retry + 1))
  if [ $_retry -gt 100 ]; then
    if [ "$_restarted" ]; then
      echo "ssh is failed. restarted but still not running"
      exit 1
    fi
    echo "ssh is failed. lets try restart the vm"
    _restarted=1

    #shutdown
    if $vmsh isRunning $osname; then
      if ! $vmsh shutdownVM $osname; then
        echo "shutdown error"
        exit 1
      fi
    fi

    while $vmsh isRunning $osname; do
      sleep 5
    done
    $vmsh closeConsole "$osname"

    #start vm
    start_and_wait
    _retry=0
  fi
done


ssh $osname sh <<EOF
echo 'StrictHostKeyChecking=no' >.ssh/config

echo "Host host" >>.ssh/config
echo "     HostName  192.168.122.1" >>.ssh/config
echo "     User $USER" >>.ssh/config
echo "     ServerAliveInterval 1" >>.ssh/config


EOF

###############################################################

if [ -e "hooks/postBuild.sh" ]; then
  echo "hooks/postBuild.sh"
  cat "hooks/postBuild.sh"
  export VM_RELEASE
  ssh -o "SendEnv=VM_RELEASE" $osname sh<"hooks/postBuild.sh"

  # Reboot here, possible there were system updates done that need
  # a reboot to take effect before more operations can be done
  restart_and_wait

  #wait for the sshd to start
  _retry=0
  while ! timeout 5 ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR $osname exit >/dev/null 2>&1; do
    echo "ssh is not ready, just wait."
    sleep 10
    _retry=$(($_retry + 1))
    if [ $_retry -gt 100 ]; then
      echo "ssh is failed."
      exit 1
    fi
  done

fi

output="$osname-$VM_RELEASE"
if [ "$VM_ARCH" ]; then
  output="$osname-$VM_RELEASE-$VM_ARCH"
fi

ssh $osname 'cat ~/.ssh/id_rsa.pub' >$output-id_rsa.pub


if [ "$VM_ENABLE_REBOOT_CRONTAB" ]; then

#upload reboot.sh
if [ -e "hooks/reboot.sh" ]; then
  echo "hooks/reboot.sh"
  cat "hooks/reboot.sh"
  scp hooks/reboot.sh $osname:/reboot.sh
else
  ssh "$osname" "cat - >/reboot.sh" <<EOF
sleep 2
for i in \$(seq 1 100) ; do 
  if ssh host exit; then
    break;
  fi
  sleep 3
done;
if ! ssh host exit; then
  #still not connected
  #shutdown
  # $VM_SHUTDOWN_CMD
  echo "Connection failed."
fi

ssh host sh <<END
env | grep SSH_CLIENT | cut -d = -f 2 | cut -d ' ' -f 1 >$osname.rebooted

END

EOF
  ssh "$osname" "cat /reboot.sh"
fi

#set cronjob
ssh "$osname" sh <<EOF
chmod +x /reboot.sh
cat /reboot.sh
if uname -a | grep SunOS >/dev/null; then
crontab -l | {  cat;  echo "* * * * * /reboot.sh";   } | crontab --
else
crontab -l | {  cat;  echo "@reboot /reboot.sh";   } | crontab -
fi
crontab -l

EOF

#VM_ENABLE_REBOOT_CRONTAB

fi


# Install any requested packages
if [ "$VM_PRE_INSTALL_PKGS" ]; then
  echo "$VM_INSTALL_CMD $VM_PRE_INSTALL_PKGS"
  ssh $osname sh <<<"$VM_INSTALL_CMD $VM_PRE_INSTALL_PKGS"
fi

if [ -e "hooks/finalize.sh" ]; then
  echo "hooks/finalize.sh"
  cat "hooks/finalize.sh"
  export VM_RELEASE
  ssh -o "SendEnv=VM_RELEASE" $osname sh<"hooks/finalize.sh"
fi

# Done!
shutdown_and_wait

##############################################################

if [ "$VM_ISO_LINK" ]; then
  echo "Clean up ISO for more space"
  sudo rm -f ${osname}.iso
fi

echo "contents of home directory:"
ls -lah

echo "free space:"
df -h



ova="$output.qcow2"
echo "Exporting $ova"
xml="$output.xml"
$vmsh exportOVA $osname "$ova" "$xml"

cp ~/.ssh/id_rsa  $output-host.id_rsa

echo "contents after export:"
ls -lah


##############################################################

echo "Checking the packages: $VM_RSYNC_PKG $VM_SSHFS_PKG"

if [ -z "$VM_RSYNC_PKG$VM_SSHFS_PKG" ]; then
  echo "skip"
else
  $vmsh addSSHAuthorizedKeys $output-id_rsa.pub
  $vmsh startVM $osname
  if [ "$VM_ENABLE_REBOOT_CRONTAB" ]; then
    $vmsh waitForVMReady $osname
  else
    while ! timeout 5 ssh $osname exit; do
      echo not ready yet, just sleep.
      sleep 5
    done
  fi
  #these packages should also be installed before.
  #so remove the following code, since openIndiana returns error 4 if sshfs is already installed.
  #if [ "$VM_RSYNC_PKG" ]; then
  #  ssh $osname sh <<<"$VM_INSTALL_CMD $VM_RSYNC_PKG"
  #fi
  #if [ "$VM_SSHFS_PKG" ]; then
  #  ssh $osname sh <<<"$VM_INSTALL_CMD $VM_SSHFS_PKG"
  #fi
  if GITHUB_ANYVM=1 ssh $osname sh -c env | grep GITHUB_ ; then
    echo "SendEnv OK"
  else
    echo "SendEnv is not working"
    echo "===============env===="
    env
    echo "=============ssh env=="
    ssh $osname sh -c env
    echo "=========check data==="
    pwd
    ls -lah .
    ls -lah ~
    ls -lah ~/.ssh
    if [ -e ~/.ssh/config ]; then
      cat ~/.ssh/config
    fi
    if [ -e ~/.ssh/config.d ]; then
      cat ~/.ssh/config.d/*
    fi
    echo "====== check data in vm===="
    ssh $osname ls -lah
    ssh $osname ls -lah .ssh
    ssh $osname cat .ssh/*
    ssh $osname cat /etc/ssh/sshd_config
    exit 1
  fi
  if [ "$osname" = "haiku" ]; then
   #it's /boot/home
   ssh $osname mkdir -p '$HOME/work'
   ssh $osname ls -lah '$HOME'
   echo "======Show ssh config: "
   ssh $osname cat /boot/system/settings/ssh/sshd_config
  else
   #check if the /home dir is writable
   ssh $osname mkdir -p $HOME/work
   ssh $osname ls -lah $HOME
   echo "======Show ssh config: "
   ssh $osname cat /etc/ssh/sshd_config
  fi
  
  
fi

echo "Build finished."


