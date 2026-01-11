

[![Build](https://github.com/anyvm-org/{{VM_OS_NAME}}-builder/actions/workflows/build.yml/badge.svg)](https://github.com/anyvm-org/{{VM_OS_NAME}}-builder/actions/workflows/build.yml)

Latest: {{LATEST_TAG}}


The image builder for `{{VM_OS_NAME}}`


All the supported releases are here:

{{RELEASE_TABLE}}



How to build:

1. Use the [manual.yml](.github/workflows/manual.yml) to build manually.
   
    Run the workflow manually, you will get a view-only webconsole from the output of the workflow, just open the link in your web browser.
   
    You will also get an interactive VNC connection port from the output, you can connect to the vm by any vnc client.

2. Run the builder locally on your Ubuntu machine.

    Just clone the repo. and run:
    ```bash
    bash build.sh {{LATEST_CONF}}
    ```
   
