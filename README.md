

[![Build](https://github.com/anyvm-org/freebsd-builder/actions/workflows/build.yml/badge.svg)](https://github.com/anyvm-org/freebsd-builder/actions/workflows/build.yml)

Latest: v1.1.4


The image builder for `freebsd`


How to use:

1. Use the [manual.yml](.github/workflows/manual.yml) to build manually.
   
    Run the workflow manually, you will get a view-only webconsole from the output of the workflow, just open the link in your web browser.
   
    You will also get an interactive VNC connection port from the output, you can connect to the vm by any vnc client.

2. Run the builder locally on your Ubuntu machine.

    Just clone the repo. and run:
    ```bash
    bash build.sh conf/freebsd-16.0.conf
    ```
   
