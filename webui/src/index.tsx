import * as React from "react";
import * as ReactDOM from "react-dom";
import { BrowserRouter as Router, Route, Link, Redirect } from "react-router-dom";
import { SomeRefComponent } from "./core";

import './desktop';

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
