package com.flamesware.nativereverb;

import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import com.facebook.react.bridge.Arguments;
import com.facebook.react.bridge.Promise;
import com.facebook.react.bridge.ReactApplicationContext;
import com.facebook.react.bridge.ReactMethod;
import com.facebook.react.bridge.ReadableMap;
import com.facebook.react.bridge.WritableMap;
import com.facebook.react.modules.core.DeviceEventManagerModule;

import org.json.JSONException;
import org.json.JSONObject;

import java.io.IOException;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

import okhttp3.*;
import okio.ByteString;

public class NativeReverbModule extends NativeReverbSpec {

    private interface AuthCallback {
        void onSuccess(String authToken);
        void onError(String code, String message);
    }

    private OkHttpClient client = null;
    private WebSocket webSocket = null;
    private String scheme = null;
    private String url = null;
    private String appKey = null;
    private String authEndpoint = null;
    private final Map<String, String> authHeaders = new HashMap<>();

    private String socketId;

    private final Map<String, Boolean> listeners = new ConcurrentHashMap<>();

    public NativeReverbModule(ReactApplicationContext reactContext) {
        super(reactContext);
    }

    private void runOnMainThread(Runnable runnable){
        new Handler(Looper.getMainLooper()).post(runnable);
    }

    private void sendEvent(String channel, String event, String data) {
        if (getReactApplicationContext().hasActiveReactInstance()) {
            WritableMap params = Arguments.createMap();
            params.putString("channel", channel);
            params.putString("event", event);
            params.putString("data", data);
            getReactApplicationContext()
                    .getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter.class)
                    .emit("ReverbEvent", params);
        }
    }

    @Override
    @ReactMethod
    public void createClient(ReadableMap options) {
        this.url = options.getString("url");
        this.appKey = options.getString("appKey");
        this.scheme = options.getString("scheme");
        if (options.hasKey("auth")) {
            ReadableMap auth = options.getMap("auth");
            if (auth != null && auth.hasKey("endpoint")) {
                authEndpoint = auth.getString("endpoint");
            }
            if (auth != null && auth.hasKey("headers")) {
                ReadableMap headersMap = auth.getMap("headers");
                if (headersMap != null) {
                    Map<String, Object> tempHeaders = headersMap.toHashMap();
                    // Convert all values to String
                    for (Map.Entry<String, Object> entry : tempHeaders.entrySet()) {
                        this.authHeaders.put(entry.getKey(), entry.getValue().toString());
                    }
                }
            }
        }
        this.client = new OkHttpClient();
    }

    @Override
    @ReactMethod
    public void connect(Promise promise) {
        Request.Builder builder = new Request.Builder().url(this.scheme + "://" + this.url + "/app/" + this.appKey);
        if(!this.authHeaders.isEmpty()){
            for (Map.Entry<String, String> entry : this.authHeaders.entrySet()) {
                builder.addHeader(entry.getKey(), entry.getValue());
            }
        }
        Request request = builder.build();
        this.webSocket = this.client.newWebSocket(request, new WebSocketListener() {
            @Override
            public void onClosed(@NonNull WebSocket webSocket, int code, @NonNull String reason) {
                super.onClosed(webSocket, code, reason);
            }

            @Override
            public void onClosing(@NonNull WebSocket webSocket, int code, @NonNull String reason) {
                super.onClosing(webSocket, code, reason);
            }

            @Override
            public void onFailure(@NonNull WebSocket webSocket, @NonNull Throwable t, @Nullable Response response) {
                runOnMainThread(() -> promise.reject("WEBSOCKET_CONNECT_ERROR",t.getMessage()));
            }

            @Override
            public void onMessage(@NonNull WebSocket webSocket, @NonNull String text) {
                try {
                    Log.d("ON_MESSAGE",text);
                    JSONObject json = new JSONObject(text);

                    if ("pusher:connection_established".equals(json.optString("event"))) {
                        JSONObject data = new JSONObject(json.getString("data"));
                        socketId = data.optString("socket_id");
                    }

                    if ("pusher:ping".equals(json.optString("event"))) {
                        JSONObject pong = new JSONObject();
                        pong.put("event", "pusher:pong");
                        webSocket.send(pong.toString());
                        return;
                    }

                    String channel = json.optString("channel","");
                    String event = json.optString("event","");
                    String key = channel + "|" + event;

                    if (listeners.containsKey(key)) {
                        sendEvent(channel, event, json.optString("data"));
                    }
                } catch (JSONException e) {
                    throw new RuntimeException(e.getMessage());
                }
            }

            @Override
            public void onMessage(@NonNull WebSocket webSocket, @NonNull ByteString bytes) {
                super.onMessage(webSocket, bytes);
            }

            @Override
            public void onOpen(@NonNull WebSocket webSocket, @NonNull Response response) {
                runOnMainThread(() -> promise.resolve(null));
            }
        });
    }

    @Override
    @ReactMethod
    public void disconnect(Promise promise) {
        if(!listeners.isEmpty()){
            listeners.clear();
        }
        if(this.webSocket != null) {
            this.webSocket.close(1000, "GoodBye");
            runOnMainThread(() -> promise.resolve(null));
        }
        else {
            runOnMainThread(() -> promise.resolve(null));
        }
    }

    private void subscribeChannel(String channel, Promise promise, String authToken){
        JSONObject msg = new JSONObject();
        JSONObject data = new JSONObject();
        try {
            data.put("channel",channel);
            data.put("auth", authToken);
            msg.put("event","pusher:subscribe");
            msg.put("data",data);
            if(webSocket.send(msg.toString())){
                runOnMainThread(() -> promise.resolve(null));
            }
            else {
                runOnMainThread(() -> promise.reject("SUBSCRIBE_ERROR","Unknown Error"));
            }
        } catch (JSONException e) {
            runOnMainThread(() -> promise.reject("SUBSCRIBE_ERROR",e.getMessage()));
        }
    }

    private void subscribeChannel(String channel, Promise promise){
        JSONObject msg = new JSONObject();
        JSONObject data = new JSONObject();
        try {
            data.put("channel",channel);
            msg.put("event","pusher:subscribe");
            msg.put("data",data);
            if(webSocket.send(msg.toString())) {
                runOnMainThread(() -> promise.resolve(null));
            }
            else {
                runOnMainThread(() -> promise.reject("SUBSCRIBE_ERROR","Unknown Error"));
            }
        } catch (JSONException e) {
            runOnMainThread(() -> promise.reject("SUBSCRIBE_ERROR",e.getMessage()));
        }
    }

    @Override
    @ReactMethod
    public void subscribe(String channel, Promise promise) {
        if(this.webSocket == null) {
            runOnMainThread(() -> promise.reject("WEBSOCKET_NOT_CONNECTED","WebSocket is not Connected"));
            return;
        }

        if(channel.startsWith("private-")){
            this.getAuthToken(channel, new AuthCallback() {
                @Override
                public void onSuccess(String authToken) {
                    subscribeChannel(channel, promise, authToken);
                }

                @Override
                public void onError(String code, String message) {
                    runOnMainThread(() -> promise.reject(code, message));
                }
            });
        }
        else {
            this.subscribeChannel(channel, promise);
        }
    }

    @Override
    @ReactMethod
    public void unsubscribe(String channel, Promise promise) {
        if(this.webSocket == null) {
            runOnMainThread(() -> promise.reject("WEBSOCKET_NOT_CONNECTED","WebSocket is not Connected"));
            return;
        }
        listeners.keySet().removeIf(key -> key.startsWith(channel + "|"));
        JSONObject msg = new JSONObject();
        JSONObject data = new JSONObject();
        try {
            data.put("channel",channel);
            msg.put("event","pusher:unsubscribe");
            msg.put("data",data);
            if(webSocket.send(msg.toString())){
                runOnMainThread(() -> promise.resolve(null));
            }
            else {
                runOnMainThread(() -> promise.reject("UNSUBSCRIBE_ERROR","Unknown Error"));
            }
        } catch (JSONException e) {
            runOnMainThread(() -> promise.reject("UNSUBSCRIBE_ERROR",e.getMessage()));
        }
    }

    @Override
    @ReactMethod
    public void listen(String channel, String event, Promise promise) {
        if(this.webSocket == null) {
            runOnMainThread(() -> promise.reject("WEBSOCKET_NOT_CONNECTED","WebSocket is not Connected"));
            return;
        }
        String key = channel + "|" + event;
        listeners.put(key, true);
        runOnMainThread(() -> promise.resolve(null));
    }

    @Override
    @ReactMethod
    public void removeListener(String channel, String event, Promise promise) {
        if(this.webSocket == null) {
            runOnMainThread(() -> promise.reject("WEBSOCKET_NOT_CONNECTED","WebSocket is not Connected"));
            return;
        }
        String key = channel + "|" + event;
        listeners.remove(key);
        runOnMainThread(() -> promise.resolve(null));
    }

    @Override
    @ReactMethod
    public void removeAllListeners(String channel, Promise promise) {
        if(this.webSocket == null) {
            runOnMainThread(() -> promise.reject("WEBSOCKET_NOT_CONNECTED","WebSocket is not Connected"));
            return;
        }
        try {
            // Remove all listeners for this channel
            listeners.keySet().removeIf(key -> key.startsWith(channel + "|"));

            // Build unsubscribe payload
            JSONObject msg = new JSONObject();
            JSONObject data = new JSONObject();
            data.put("channel", channel);
            msg.put("event", "pusher:unsubscribe");
            msg.put("data", data);

            if (webSocket.send(msg.toString())) {
                runOnMainThread(() -> promise.resolve(null));
            } else {
                runOnMainThread(() -> promise.reject("REMOVE_ALL_LISTENERS_ERROR", "Failed to send unsubscribe message"));
            }
        } catch (JSONException e) {
            runOnMainThread(() -> promise.reject("REMOVE_ALL_LISTENERS_ERROR", e.getMessage()));
        }
    }

    private void getAuthToken(String channel, final AuthCallback callback) {
        if (this.authEndpoint == null) {
            runOnMainThread(() -> callback.onError("AUTH_ENDPOINT_NOT_SET", "No authEndpoint provided"));
            return;
        }
        OkHttpClient httpClient = new OkHttpClient();
        // Laravel expects POST for auth
        RequestBody body = new FormBody.Builder()
                .add("channel_name", channel)
                .add("socket_id",this.socketId)
                .build();
        Request.Builder builder = new Request.Builder()
                .url(this.authEndpoint)
                .post(body);

        // Add auth headers if needed (Bearer token, etc.)
        for (Map.Entry<String, String> entry : authHeaders.entrySet()) {
            builder.addHeader(entry.getKey(), entry.getValue());
        }

        Request request = builder.build();

        httpClient.newCall(request).enqueue(new Callback() {
            @Override
            public void onFailure(@NonNull Call call, @NonNull IOException e) {
                runOnMainThread(() -> callback.onError("AUTH_FAILED", e.getMessage()));
            }

            @Override
            public void onResponse(@NonNull Call call, @NonNull Response response) throws IOException {
                if (!response.isSuccessful()) {
                    runOnMainThread(() -> callback.onError("AUTH_FAILED", "HTTP " + response.code()));
                    return;
                }
                ResponseBody responseBody = response.body();
                if (responseBody == null) {
                    runOnMainThread(() -> callback.onError("AUTH_FAILED", "Empty response body"));
                    return;
                }
                String body = responseBody.string();
                responseBody.close();
                try {
                    JSONObject json = new JSONObject(body);
                    String authToken = json.getString("auth");
                    callback.onSuccess(authToken);
                } catch (JSONException e) {
                    runOnMainThread(() -> callback.onError("AUTH_FAILED", e.getMessage()));
                }
            }
        });
    }

}
