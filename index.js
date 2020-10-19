const core = require('@actions/core');
const exec = require('@actions/exec');
const tc = require('@actions/tool-cache');
const io = require('@actions/io');
const fs = require("fs");



async function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms))
}

async function vboxmanage(vmName, cmd, args = "") {
  await exec.exec("sudo  vboxmanage " + cmd + "   " + vmName + "   " + args);
}

async function getScreenText(vmName) {
  let png = path.join(__dirname, "/screen.png");
  await vboxmanage(vmName, "controlvm", "screenshotpng  " + png);
  await exec.exec("sudo chmod 666 " + png);
  let output = "";
  await exec.exec("pytesseract  " + png, [], {
    listeners: {
      stdout: (s) => {
        output += s;
      }
    }
  });
  return output;
}

async function waitFor(vmName, tag) {

  let slept = 0;
  while (true) {
    slept += 1;
    if (slept >= 300) {
      throw new Error("Timeout can not boot");
    }
    await sleep(1000);

    let output = await getScreenText(vmName);

    if (tag) {
      if (output.includes(tag)) {
        core.info("OK");
        await sleep(1000);
        return true;
      } else {
        core.info("Checking, please wait....");
      }
    } else {
      if (!output.trim()) {
        core.info("OK");
        return true;
      } else {
        core.info("Checking, please wait....");
      }
    }

  }

  return false;
}

// most @actions toolkit packages have async methods
async function run() {
  try {
    let sshport = 2222;
    fs.appendFileSync(path.join(process.env["HOME"], "/.ssh/config"), "Host freebsd " + "\n");
    fs.appendFileSync(path.join(process.env["HOME"], "/.ssh/config"), " User root" + "\n");
    fs.appendFileSync(path.join(process.env["HOME"], "/.ssh/config"), " HostName localhost" + "\n");
    fs.appendFileSync(path.join(process.env["HOME"], "/.ssh/config"), " Port " + sshport + "\n");
    fs.appendFileSync(path.join(process.env["HOME"], "/.ssh/config"), "StrictHostKeyChecking=accept-new\n");


    core.info("Install tesseract");
    await exec.exec("brew install tesseract");
    await exec.exec("pip3 install pytesseract");


    let ext = "https://download.virtualbox.org/virtualbox/6.1.14/Oracle_VM_VirtualBox_Extension_Pack-6.1.14.vbox-extpack";
    //install ext for debug purpose



    let imgName = "FreeBSD-12.1-RELEASE-amd64";
    let url = "https://download.freebsd.org/ftp/releases/VM-IMAGES/12.1-RELEASE/amd64/Latest/" + imgName + ".vhd.xz";
    core.info("Downloading image: " + url);
    let img = await tc.downloadTool(url);
    core.info("Downloaded file: " + img);
    let vhd = imgName + ".vhd";
    await io.mv(img, "./" + vhd + ".xz");
    await exec.exec("xz -d -T 0 --verbose " + vhd + ".xz");

    let vmName = "freebsd";
    core.info("Create VM");
    await exec.exec("sudo vboxmanage  createvm  --name " + vmName + " --ostype FreeBSD_64  --default   --basefolder freebsd --register");

    await vboxmanage(vmName, "storagectl", "  --name SATA --add sata  --controller IntelAHCI ")

    await vboxmanage(vmName, "storageattach", "    --storagectl SATA --port 0  --device 0  --type hdd --medium " + vhd);

    await vboxmanage(vmName, "modifyvm ", " --vrde on  --vrdeport 33389");

    await vboxmanage(vmName, "modifyvm ", "  --natpf1 'guestssh,tcp,," + sshport + ",,22'");

    await vboxmanage(vmName, "modifyhd ", vhd + " --resize  100000");

    await vboxmanage(vmName, "startvm ", " --type headless");


    core.info("sleep 300 seconds for first boot");
    let loginTag = "FreeBSD/amd64 (freebsd) (ttyv0)";

    await waitFor(loginTag);

    core.info("Enable ssh");

    let init = __dirname + "/init.txt";
    core.info(init);
    await vboxmanage(vmName, "controlvm ", " keyboardputfile ", init);

    await exec.exec("ssh freebsd", [], { input: 'ssh-keygen -t rsa -f ~/.ssh/id_rsa -q -N ""' });
    await exec.exec("ssh freebsd", [], { input: 'echo "StrictHostKeyChecking=accept-new" >>~/.ssh/config' });

    let sshkey = "";
    await exec.exec("ssh freebsd", [], {
      input: 'cat ~/.ssh/id_rsa.pub', listeners: {
        stdout: (s) => {
          sshkey += s;
        }
      }
    });

    core.info("sshkey:" + sshkey);

    fs.writeFileSync(__dirname + "/id_rsa.pub", sshkey);

    core.info("Power off");
    await exec.exec("ssh freebsd", [], { input: 'shutdown -p now' });

    while (true) {
      core.info("Sleep 2 seconds");
      await sleep(2000);
      let std = "";
      await exec.exec("sudo vboxmanage list runningvms", [], {
        listeners: {
          stdout: (s) => {
            std += s;
            core.info(s);
          }
        }
      });
      if (!std) {
        core.info("shutdown OK continue.");
        await sleep(2000);
        break;
      }
    }

    let ova = "freebsd-12.1.ova";
    core.info("Export " + ova);
    await vboxmanage(vmName, "export", "--output " + ova);
    await exec.exec("sudo chmod 666 " + ova);

    core.info("Compress " + vhd);
    await exec.exec("7z a freebsd-12.1.7z  id_rsa.pub " + ova);

  } catch (error) {
    core.setFailed(error.message);
  }
}

run();
