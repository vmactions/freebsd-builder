const core = require('@actions/core');
const exec = require('@actions/exec');
const tc = require('@actions/tool-cache');
const io = require('@actions/io');
const fs = require("fs");



async function sleep (ms) {
  return new Promise(resolve => setTimeout(resolve, ms))
}


// most @actions toolkit packages have async methods
async function run() {
  try {
    core.info("Install tesseract");
    await exec.exec("brew install tesseract");
    await exec.exec("pip3 install pytesseract");


    let ext="https://download.virtualbox.org/virtualbox/6.1.14/Oracle_VM_VirtualBox_Extension_Pack-6.1.14.vbox-extpack";
    //install ext for debug purpose


    core.info("Downloading image:");
    let imgName = "FreeBSD-12.1-RELEASE-amd64";
    let url="https://download.freebsd.org/ftp/releases/VM-IMAGES/12.1-RELEASE/amd64/Latest/"+imgName+".vhd.xz";
    let img = await tc.downloadTool(url);
    core.info("Downloaded file: " + img);
    let vhd = imgName + ".vhd";
    await io.mv(img, "./" + vhd + ".xz");
    await exec.exec("xz -d -T 0 --verbose " + vhd + ".xz");

    let vmName = "freebsd";
    core.info("Create VM");
    await exec.exec("sudo vboxmanage  createvm  --name " + vmName + " --ostype FreeBSD_64  --default   --basefolder freebsd --register");
    
    await exec.exec("sudo vboxmanage  storagectl " + vmName + "  --name SATA --add sata  --controller IntelAHCI ");
    
    await exec.exec("sudo vboxmanage  storageattach "+ vmName + "    --storagectl SATA --port 0  --device 0  --type hdd --medium " + vhd);
    
    await exec.exec("sudo  vboxmanage modifyvm "+ vmName + " --vrde on  --vrdeport 33389");

    await exec.exec("sudo vboxmanage modifyvm "+ vmName + "  --natpf1 'guestssh,tcp,,2222,,22'");

    await exec.exec("sudo  vboxmanage modifyhd " + vhd + " --resize  100000");
    
    await exec.exec("sudo vboxmanage startvm " + vmName + " --type headless");


    core.info("sleep 300 seconds for first boot");
    let loginTag="FreeBSD/amd64 (freebsd) (ttyv0)"
    let slept = 0;
    while(true) {
      slept +=20;
      if(slept >= 300) {
        throw new Error("Timeout can not boot");
      }
      await sleep(20000);

      await exec.exec("sudo  vboxmanage  controlvm " + vmName + "  screenshotpng  screen.png")


      await exec.exec("sudo chmod 666 screen.png");

      let output="";
      await exec.exec("pytesseract  screen.png", [] , {listeners:{stdout:(s)=>{
        output += s;
      }}});
    
      
      if(output.includes(loginTag)) {
        core.info("Login ready, sleep last 10 seconds");
        await sleep(5000);
        break;
      } else {
        core.info("The VM is booting, please wait....");
      }

    }

    core.info("Enable ssh");

    let home = process.env["HOME"]
    fs.appendFileSync(home + "/.ssh/config", "StrictHostKeyChecking=accept-new\n")
    

    let init = __dirname + "/init.txt"; 
    core.info(init);
    await exec.exec("sudo vboxmanage controlvm " + vmName + " keyboardputfile ", init);

    await exec.exec("ssh -p 2222 root@localhost", [], {input: 'ssh-keygen -t rsa -f ~/.ssh/id_rsa -q -N ""'});
    await exec.exec("ssh -p 2222 root@localhost", [], {input: 'echo "StrictHostKeyChecking=accept-new" >>~/.ssh/config'});
  
    let sshkey = "";
    await exec.exec("ssh -p 2222 root@localhost", [], {input: 'cat ~/.ssh/id_rsa.pub', listeners:{stdout:(s)=>{
      sshkey += s;
    }}});

    core.info("sshkey:" + sshkey);

    fs.writeFileSync(__dirname + "/id_rsa.pub", sshkey);

    await exec.exec("sudo vboxmanage controlvm "+ vmName + " poweroff");

  } catch (error) {
    core.setFailed(error.message);
  }
}

run();
