# Issue #244: laptop mouse on the controller page

- `probe.js` is a Node + Playwright probe. It runs in headless installed Chrome, with a routed stub WebSocket standing in for the host. The run steps are in its header.
- `probe-output.txt` is the raw output, ending `ALL PASSED`. It covers:
  - (a) locked mouse moves send the same input frames as an equivalent touch drag in a mobile context, and Esc zeroes the input;
  - (b) the sensitivity slider scales the moves;
  - (c) a mobile context shows no capture affordance.
- `desktop-playing.png` and `mobile-playing.png` are the controller in play on desktop and on mobile.

**Stubbed:** headless Chrome won't grant a real pointer lock, so the probe stubs `requestPointerLock` and `exitPointerLock`.

**Deviation:** the mouse point is clamped to the drag disc; a touch point is not. Inside the disc the frames are identical. Past the edge, reversing the mouse takes effect immediately, where a finger has to travel back to the edge first. With a mouse there's no physical edge to feel, so the unclamped version would feel like wind-up lag.
