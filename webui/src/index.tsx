import * as React from "react";
import * as ReactDOM from "react-dom";
import { BrowserRouter as Router, Route, Link, Redirect } from "react-router-dom";

export interface PathProps { path: string; }

interface SomeRefState {
    kind: string;
    body: any;
};

export interface X11Desktop {
    displayId?: string;
    xauthorityPath?: string;
    virtual: boolean;
}

export interface RefProps { 
    path: string; 
    body: X11Desktop;
}

export class DesktopComponent extends React.Component<RefProps, {}> {
    constructor(props: RefProps) {
        super(props);
    }

    render() {
        return <div>connecting to {this.props.path}desktopStream/...</div>
    }
}

export class X11DesktopComponent extends React.Component<RefProps, {}> {
    render() {
        return (
            <div>
                X11Desktop
                <SomeRefComponent path={this.props.path + "desktop/"} />
            </div>
        );
    }
}

export class SomeRefComponent extends React.Component<PathProps, SomeRefState> {
    constructor(props: PathProps) {
        super(props);
        this.state = {kind: null, body: null};
    }

    async componentWillMount() {
        let resp = await fetch("/api" + this.props.path, {
            credentials: "include",
        });
        this.setState({
            kind: resp.headers.get("x-document-type"),
            body: await resp.json()
        });
    }

    render() {
        var innerComponent: any = null
        if (this.state.kind == "X11Desktop") {
            innerComponent = <X11DesktopComponent body={this.state.body} path={this.props.path} />;
        } else if (this.state.kind == "Desktop") {
            innerComponent = <DesktopComponent body={this.state.body} path={this.props.path} />;
        } else if (this.state.kind) {
            innerComponent = (
                <div>
                    Unknown reference type <code>{this.state.kind}</code>:
                    <pre>{JSON.stringify(this.state.body)}</pre>
                </div>
            );
        }

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

function RefRoute({match} : {match : any}) {
    let path: string = match.params.path;
    if (!path.endsWith("/")) {
        return <Redirect to={"/ref/" + path + "/"} />;
    }
    return <SomeRefComponent path={"/" + path} />;
}

const AppRouter = () => (
    <Router>
        <div>
            <Link to="/">Home</Link>
            <Route path="/ref/:path(.+)" component={RefRoute} />
        </div>
    </Router>
)

ReactDOM.render(
    AppRouter(),//<AppRouter compiler="TypeScript" framework="React" />,
    document.getElementById("body")
);
