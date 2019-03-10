import { SomeRefComponent, RefProps, Metadata, registerMetacComponent } from "./core";
import * as React from "react";

interface FileEntry {
    name: string;
    isDirectory: boolean;
};

interface FsListing {
    isAccessible: boolean;
    entries: FileEntry[];
};

