# tradeview-devnet-script

This repository provides ubuntu 22.04 and 24.04 script for running a node on tradeview devnet:

System Requirements:

- Operating System: Ubuntu 22.04 or 24.04
- Memory: At least 4GB RAM
- Storage: Minimum 20GB available disk space
- Network: Stable internet connection

Clone this repo using:
git clone '<https://github.com/tradeview-local/tradeview-devnet-node-script.git>'

Setup the node:
open a terminal window and run the following command:

```bash
./tradeview_ubuntu_node.sh
```

once it finishes, start the node service with the following command:

```bash
sudo systemctl start tradeviewchain.service
```

check the node logs with the following command:

```bash
journalctl -u tradeviewchain.service -f
```
