# metac

*Warning: this is rewrite of MetaContainer - it is not yet ready to use in production. Subscribe for newletter at https://metacontainer.org/*

MetaContainer aims to provide a common interface for sharing various types of resources, including filesystems, Ethernet networks or USB devices in a **secure way**. MetaContainer also provides compute services (container orchestration) with the ability to seamlessly attach possibly remote resources.

[Documentation](doc/index.md) | [Install guide](#installing-metacontainer)

## What can MetaContainer do?

- Share a folder between computers ([view tutorial](tutorial/file.md)):

    ```
    user@host1$ metac fs export /home/user/shared
    ref:7N9_k-ZQJ92SyZMQtizkA4mYDoG-Byhes6Nok1ph
    Send the reference via IM or mail to another person or run on another computer:
    user@host2$ metac fs bind /home/user/shared-from-host1 ref:7N9_k-ZQJ92SyZMQtizkA4mYDoG-Byhes6Nok1ph
    ```

- Share a desktop session with another person ([view tutorial](tutorial/desktop.md))

    ```
    user@host1$ metac desktop export localx11:
    ref:MNS2I2mR4nsVW4XYVI3r-1TkmScK0OZd6X_rB5qL
    Send the reference via IM or mail to another person, so she can attach to your session:
    user@host2$ metac desktop attach ref:MNS2I2mR4nsVW4XYVI3r-1TkmScK0OZd6X_rB5qL
    ```

- Launch a virtual machine with a disk image residing on another computer (e.g. NAS)

    On machine hosting the disk:

    ```
    user@nas$ metac file export /dev/mapper/nas-vm
    ref:miOZCkUt77meIs-1HsK65Qb2U-_DHV2eC9yAjLiZ
    ```

    On machine where the VM should be ran:

    ```
    user@host$ metac vm start --drive uri=ref:miOZCkUt77meIs-1HsK65Qb2U-_DHV2eC9yAjLiZ
    ```


- Run a process using Nim API:

    ```nim
    let dir = await fsFromUri(instance, "local:/bin")

    let config = ProcessEnvironmentDescription(
      memory: 512,
      filesystems: @[FsMount(path: "/bin", fs: dir)]
    )

    let processConfig = ProcessDescription(
      args: @["/bin/busybox", "sleep", "3"]
    )

    await launcher.launch(processConfig, config)
    ```

## Quick start

### Installing MetaContainer

Quick install:

```
curl https://metacontainer.org/install.sh | sudo bash
```

Alternatively, on Ubuntu/Debian (x86_64) based distributions execute the following commands:

```
sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv F562C6B09C9C2AA9A8D82D4CF190C4CD1C66C328
echo 'deb https://metacontainer.org/repo/ any metac | sudo tee /etc/apt/sources.list.d/metac.list
sudo apt-get install -y apt-transport-https
sudo apt-get update
sudo apt-get install -y metac
```

For other distros, download https://metacontainer.org/repo/metac-latest.tar.xz and unpack it somewhere (preferably to root directory).

### Installing from source

MetaContainer needs to build quite a few dependencies, so it uses [Nix](https://nixos.org/nix) package manager to manage the process. If you don't already have it, grab it from [its homepage](https://nixos.org/nix).

Then building MetaContainer is as simple as executing `nix-build -A release.metac`. If you want to build Debian package, run `nix-build -A release.metacDeb`.

*Warning: * building MetaContainer will take about 2 hours on good hardware (it needs to build *lots* of dependencies, including Linux kernel for VMs). Subseqent build (even full rebuilds) will take less then 2 minutes.

## Users

Most of MetaContainer functionality can currently only be managed by root. Many services are sandboxed, so if you are going to use MetaContainer on a single user machine, you should not be concerned. (that is actually the reason some services can't be ran by normal user --- e.g. normal users can't chroot).

`sound` and `desktop` service should be ran by normal user for better intergration with desktop. To do it, you need to allow you user to create MetaContainer services:

```
echo METAC_ALLOWED_USERS=$(id -u) > /etc/default/metac
systemctl restart metac.target
```

And enable `metac-user.target` using user systemd:

```
systemctl --user enable metac-user.target
systemctl --user start metac-user.target
```

## Brief of the MetaContainer architecture

You may also want to read (a bit outdated) [paper describing MetaContainer](https://users.atomshare.net/~zlmch/metac.pdf).
