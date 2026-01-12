Make sure to have libuv and cJSON development headers installed. Once installed, compile with `make` and run it from build directory.

The easiest way to test is by using [GNU Netcat](https://netcat.sourceforge.net/).

## Events

You can comminucate with server and other clients by using events.

### Event types

- Request / Response: A request requires the receiver to return a matching response
- Broadcast: A message sent to all connected clients except the sender
- Notify: Messages sent from the server to clients

### Event structure

```json
{ "event": "<event_name>", "data": {}, "to_host": false }
```

### List of events
