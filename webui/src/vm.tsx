import { SomeRefComponent, RefProps, Metadata, registerMetacComponent } from "./core";
import * as React from "react";

interface FileRef {}
interface FilesystemRef {}

enum VmState {
    running = "running",
    turnedOff = "turnedOff"
}

enum DriveDriver {
    virtio = "virtio", ide = "ide"
}

interface Drive {
    driver: DriveDriver;
    device: FileRef;
}

interface BootKernel {
    kernel: FileRef;
    initrd?: FileRef;
    cmdline: string;
}

enum SerialPortDriver {
    default = "default", virtio = "virtio"
}

interface SerialPort {
    driver: SerialPortDriver;
    name: string;
    nowait: boolean;
}

enum VMFilesystemDriver {
    virtio9p = "virtio9p"
}

interface VmFilesystem {
    driver: VMFilesystemDriver;
    name: string;
    fs: FilesystemRef;
}

interface Vm {
    meta: Metadata;
    state?: VmState;
    memory: number;
    vcpu: number;

    bootDisk?: number;
    bootKernel?: BootKernel;

    drives: Drive[];
    filesystems: VmFilesystem[];
    serialPorts: SerialPort[];
}

export class VmComponent extends React.Component<RefProps<Vm>, {}> {
    constructor(props: RefProps<Vm>) {
        super(props);
    }

    render() {
        return (
            <div>
                A virtual machine.
            </div>
        )
    }
}

