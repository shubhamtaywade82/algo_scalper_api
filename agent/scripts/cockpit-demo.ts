/**
 * Offline demo of the operator cockpit: no Dhan credentials, no network. The agent runs against
 * fakes (no market data, paper venue), so the screen shows an idle, healthy session.
 *
 *   npm run cockpit:demo
 */
import { createElement } from 'react';
import { render } from 'ink';
import App from '../src/ui/App.js';
import { fakeRuntime } from '../tests/support/fakeRuntime.js';

const { runtime, stop } = fakeRuntime();
runtime.logger.info('demo session: synthetic environment, no broker connection');
const instance = render(createElement(App, { runtime }), { exitOnCtrlC: false });
void instance.waitUntilExit().then(() => stop());
