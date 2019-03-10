import * as React from "react";

export interface PathProps { path: string; }

interface SomeRefState {
    kind: string;
    body: any;
};

export interface RefProps<T> { 
    path: string; 
    body: T;
}

export interface Metadata {
    name: string;
};

var components: {[id: string]:(props: any)=>any;} = {}

export function registerMetacComponent(name: string, func: (props: any)=>any) {
    components[name] = func;
}

export class SomeRefComponent extends React.Component<PathProps, SomeRefState> {
    constructor(props: PathProps) {
        super(props);
        this.state = {kind: null, body: null};
    }

    async componentWillMount() {
        var resp
        try {
            resp = await fetch("/api" + this.props.path, {
                credentials: "include",
            });
        } catch(ex) {
            console.log("error", ex);
            return;
        }
        this.setState({
            kind: resp.headers.get("x-document-type"),
            body: await resp.json()
        });
    }

    render() {
        var innerComponent: any = null
        if (components[this.state.kind]) {
            innerComponent = components[this.state.kind]({path: this.props.path, body: this.state.body});
        } else if (this.state.kind) {
            innerComponent = (
                <div>
                    Unknown reference type <code>{this.state.kind}</code>:
                    <pre>{JSON.stringify(this.state.body)}</pre>
                </div>
            );
        }
        console.log(innerComponent);

        return (
            <div style={{border: "1px solid gray", padding: "0.5em"}}>
                <div>{this.props.path} ({this.state.kind})</div>
                <div>
                    {!this.state.kind && "Loading..."}
                    {innerComponent}
                </div>
            </div>)
        ;
    }
}