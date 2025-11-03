


if [ "$VM_ARCH" = "riscv64" ]; then
  #for riscv64
  waitForText "7. Boot Options" 20
  sleep  20
  inputKeys "enter"
  clear
fi


waitForText "$VM_LOGIN_TAG"

