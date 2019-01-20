import * as React from "react";
import * as ReactDOM from "react-dom";
import { BrowserRouter as Router, Route, Link } from "react-router-dom";

export interface HelloProps { compiler: string; framework: string; }

// 'HelloProps' describes the shape of props.
// State is never set so we use the '{}' type.
export class Hello extends React.Component<HelloProps, {}> {
    render() {
        return <h1>Hello from {this.props.compiler} and {this.props.framework}!</h1>;
    }
}

const AppRouter = () => (
    <Router>
        <div>
            <Link to="/hello">open hello</Link>
            <Route path="/hello" exact component={Hello} />
        </div>
    </Router>
)

ReactDOM.render(
    AppRouter(),//<AppRouter compiler="TypeScript" framework="React" />,
    document.getElementById("body")
);
