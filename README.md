# React Native Reverb

A React Native TurboModule wrapper for Laravel Reverb WebSockets.  
This package lets you connect to a Reverb server, subscribe/unsubscribe to channels, and listen for broadcasted events & notifications.

---

## 🚀 Installation

### From npm
```sh
npm install react-native-reverb
````
### or with yarn:

```sh
yarn add react-native-reverb
```

---

## 📦 Setup

1. **Autolinking (React Native 0.71+)**
   The package supports autolinking, no extra linking step required.

2. **iOS**
   Install pods:

   ```sh
   cd ios && pod install
   ```

3. **Android**
   Nothing extra required, autolinking will register the TurboModule.

---

## 🛠 Usage

```tsx
import { ReverbClient } from 'react-native-reverb';

const client = new ReverbClient({
  appKey: '<YOUR_REVERB_APP_KEY>',
  scheme: 'https',
  url: '<YOUR_REVERB_HOST>',
  auth: {
    endpoint: '<YOUR_REVERB_AUTH_ENDPOINT>',
    headers: {
      Authorization: `Bearer <TOKEN>`,
    },
  },
});

// Connect to server
await client.connect();

// Subscribe to a channel
const channel = await client.private(`App.Models.Order.${orderId}`);

// Listen for specific event
channel.listen('OrderUpdated', (data: any) => {
  console.log('Order updated:', data);
});

// Listen for Laravel notifications
channel.notifications((notification: any) => {
  console.log('Notification received:', notification);
});

// Remove all Listeners and unsubscribe at once when leaving
await channel.removeAllListeners();

// Disconnect Websocket completely
await client.disconnect();
```

---

## 📚 API Reference

### `ReverbClient`

* `new ReverbClient(options: NativeReverbOptions): ReverbClient` – create a client instance
* `connect(): Promise<void>` – connect to Reverb server
* `disconnect(): Promise<void>` – disconnect & cleanup
* `channel(name: string): Promise<ReverbChannel>` – subscribe to a public channel
* `private(name: string): Promise<ReverbPrivateChannel>` – subscribe to a private channel

### `ReverbChannel` | `ReverbPrivateChannel`

* `listen(event: string, callback: (data: any) => void): Promise<void>` – listen for events
* `notifications(callback: (data: any) => void): Promise<void>` – listen for Laravel notifications
* `removeListener(event: string): Promise<void>` – stop listening to an event
* `removeAllListeners(): Promise<void>` – stop listening from all events and unsusbcribe the channel
* `unsubscribe(): Promise<void>` – unsubscribe from this channel
* `getChannelName(): string` - get channel name

---

## 🧑‍💻 Development

Clone the repo and install dependencies:

```sh
git clone https://github.com/azlanali076/react-native-reverb.git
cd react-native-reverb
npm install
```

---

## 📄 License

MIT © [Syed Azlan Ali](https://github.com/azlanali076)

