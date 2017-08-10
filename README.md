# metac

MetaContainer aims to provide a common interface for sharing various types of resources, including filesystems, Ethernet networks or USB devices in a **secure way**. MetaContainer also provides compute services (container orchestration) with the ability to seamlessly attach possibly remote resources.

## What can MetaContainer do?

- Share a folder between computers

    ```
    user@host1$ metac fs export local:/home/user/shared
    ref://[fd6f:e1da:f01c::91f1]/EQHCf25ldHdvcmv_jd-f0AgMxgkBlW3GvIllvw4
    user@host2$ metac fs bind /home/user/shared-from-host1 'ref://[fd6f:e1da:f01c::91f1]/EQHCf25ldHdvcmv_jd-f0AgMxgkBlW3GvIllvw4'
    ```

- Like `chroot`, but runs in an isolated VM:

   ```
   user@host$ metac run --mount=/=local:$PWD/mychroot --pty --service=computevm bash
   ```

- Launch a virtual machine with a disk image residing on another computer (e.g. NAS)

    ```
    user@nas$ metac file export /dev/mapper/nas-vm
    ref://[fd6f:e1da:f01c::91f1]/EQHCf25ldHdvcmv_jd-f0AgMxgkBlW3GvIllvw4
    user@host$ metac vm start --drive 'uri=ref://[fd6f:e1da:f01c::91f1]/EQHCf25ldHdvcmv_jd-f0AgMxgkBlW3GvIllvw4'
    ```

- Create Ethernet tunnel between two computers

   ```
   user@host1$ metac net export newlocal:tunnel0
   ref://[fd6f:e1da:f01c::91f1]/EQHCf25ldHdvcmv_jd-f0AgMxgkBlW3GvIllvw4
   user@host2$ metac net bind newlocal:tunnel0 'ref://[fd6f:e1da:f01c::91f1]/EQHCf25ldHdvcmv_jd-f0AgMxgkBlW3GvIllvw4'
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

- Attach to a desktop session running on another computer:

    ```
    user@host1$ metac desktop export localx11:
    ref://[fd6f:e1da:f01c::91f1]/EQHCf25ldHdvcmv_jd-f0AgMxgkBlW3GvIllvw4
    user@host2$ metac desktop attach 'ref://[fd6f:e1da:f01c::91f1]/EQHCf25ldHdvcmv_jd-f0AgMxgkBlW3GvIllvw4'
    ```

## Brief of MetaContainer architecture

You may also want to read (a bit outdated) [paper describing MetaContainer](https://users.atomshare.net/~zlmch/metac.pdf).
