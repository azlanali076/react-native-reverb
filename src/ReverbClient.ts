import { DeviceEventEmitter, EmitterSubscription } from "react-native";
import NativeReverb, { NativeReverbOptions } from "./specs/NativeReverb";

const callbacks: Record<string, (data: any) => void> = {};
const NOTIFICATION =
  "Illuminate\\Notifications\\Events\\BroadcastNotificationCreated";

class ReverbChannel {
  constructor(protected channel: string) {}

  getChannelName() {
    return this.channel;
  }

  async listen(event: string, cb: (data: any) => void) {
    const key = `${this.channel}|${event}`;
    if (callbacks[key]) {
      delete callbacks[key];
      await NativeReverb.removeListener(this.channel, event);
    }
    callbacks[key] = cb;
    await NativeReverb.listen(this.channel, event);
  }

  async notifications(cb: (data: any) => void) {
    const key = `${this.channel}|${NOTIFICATION}`;
    callbacks[key] = cb;
    await NativeReverb.listen(this.channel, NOTIFICATION);
  }

  async stopListenForNotifications() {
    const key = `${this.channel}|${NOTIFICATION}`;
    if (callbacks[key]) {
      delete callbacks[key];
    }
    await NativeReverb.removeListener(this.channel, NOTIFICATION);
  }

  async removeListener(event: string) {
    await NativeReverb.removeListener(this.channel, event);
    const key = `${this.channel}|${event}`;
    if (callbacks[key]) {
      delete callbacks[key];
    }
  }

  async removeAllListeners() {
    Object.keys(callbacks).forEach((key) => {
      if (key.startsWith(`${this.channel}|`)) {
        delete callbacks[key];
      }
    });
    return await NativeReverb.removeAllListeners(this.channel);
  }

  async unsubscribe() {
    Object.keys(callbacks).forEach((key) => {
      if (key.startsWith(`${this.channel}|`)) {
        delete callbacks[key];
      }
    });
    return await NativeReverb.unsubscribe(this.channel);
  }
}

class ReverbPrivateChannel extends ReverbChannel {
  constructor(channel: string) {
    super(channel);
  }

  getChannelName(): string {
    return this.channel.replace("private-", "");
  }
}

export class ReverbClient {
  private eventSubscription: EmitterSubscription | null;

  constructor(options: NativeReverbOptions) {
    this.eventSubscription = DeviceEventEmitter.addListener(
      "ReverbEvent",
      (payload) => {
        const { channel, event, data } = payload;
        const key = `${channel}|${event}`;

        if (callbacks[key]) {
          try {
            const parsedData = JSON.parse(data);
            callbacks[key](
              event === NOTIFICATION
                ? parsedData
                : parsedData.data ?? parsedData
            );
          } catch {
            callbacks[key](data);
          }
        } else {
          console.log(`No callback for ${channel}|${event}`);
        }
      }
    );
    this.createClient(options);
  }

  removeListener() {
    if (this.eventSubscription) {
      this.eventSubscription.remove();
      this.eventSubscription = null;
    }
  }

  destroy() {
    this.removeListener();
  }

  private createClient(options: NativeReverbOptions) {
    return NativeReverb.createClient(options);
  }

  async connect() {
    return await NativeReverb.connect();
  }

  async disconnect() {
    this.removeListener();
    return await NativeReverb.disconnect();
  }

  async channel(channel: string) {
    await NativeReverb.subscribe(channel);
    return new ReverbChannel(channel);
  }

  async private(channel: string) {
    await NativeReverb.subscribe(`private-${channel}`);
    return new ReverbPrivateChannel(`private-${channel}`);
  }
}

export type IReverbChannel = InstanceType<typeof ReverbChannel>;
export type IReverbPrivateChannel = InstanceType<typeof ReverbPrivateChannel>;
