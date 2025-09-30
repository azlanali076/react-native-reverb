import { type TurboModule } from "react-native";
import { TurboModuleRegistry } from "react-native";

export interface NativeReverbOptions {
  url: string;
  appKey: string;
  scheme: string;
  auth?: {
    endpoint: string;
    headers?: { [key: string]: string };
  };
}

export interface Spec extends TurboModule {
  createClient(options: NativeReverbOptions): void;
  connect(): Promise<void>;
  disconnect(): Promise<void>;

  subscribe(channel: string): Promise<void>;
  unsubscribe(channel: string): Promise<void>;

  listen(channel: string, event: string): Promise<void>;
  removeListener(channel: string, event: string): Promise<void>;
  removeAllListeners(channel: string): Promise<void>;
}

export default TurboModuleRegistry.getEnforcing<Spec>("NativeReverb");
