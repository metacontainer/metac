import { SomeRefComponent, RefProps, registerMetacComponent } from "./core";
import * as React from "react";
import { VncDisplay } from 'react-vnc-display';

export interface X11Desktop {
    displayId?: string;
    xauthorityPath?: string;
    virtual: boolean;
}

export interface Desktop {
    supportedFormats: string[];
}

export class DesktopComponent extends React.Component<RefProps<Desktop>, {}> {
    constructor(props: RefProps<Desktop>) {
        super(props);
    }

    render() {
        if (this.props.body.supportedFormats.indexOf("vnc") == -1) {
            return <div>(this display doesn't support VNC, can't connect)</div>
        }
        let url = (location.protocol=="https:"?"wss":"ws") + "://" + location.host + '/api' + this.props.path + "desktopStream/?format=vnc";

        return (
            <div>
                <div>display: {this.props.path}desktopStream/</div>
                <VncDisplay url={url} />
            </div>
        )
    }
}

registerMetacComponent("Desktop", (props: any) => React.createElement(DesktopComponent, props));

export class X11DesktopComponent extends React.Component<RefProps<X11Desktop>, {}> {
    render() {
        return (
            <div>
                X11Desktop
                <SomeRefComponent path={this.props.path + "desktop/"} />
            </div>
        );
    }
}

registerMetacComponent("X11Desktop", (props: any) => React.createElement(X11DesktopComponent, props));
