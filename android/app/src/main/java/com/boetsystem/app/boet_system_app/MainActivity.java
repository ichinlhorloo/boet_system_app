package com.boetsystem.app.boet_system_app;

import android.app.DownloadManager;
import android.content.Context;
import android.net.Uri;
import android.os.Bundle;
import android.os.Environment;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.widget.Toast;

import androidx.annotation.NonNull;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

public class MainActivity extends FlutterActivity {
    private static final String CHANNEL = "com.boetsystem.app/download";
    private static final String TAG = "MainActivity";

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);

        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), CHANNEL)
                .setMethodCallHandler(
                        (call, result) -> {
                            if (call.method.equals("downloadFile")) {
                                String url = call.argument("url");
                                String filename = call.argument("filename");
                                String cookie = call.argument("cookie");

                                Log.d(TAG, "Download method called");
                                Log.d(TAG, "URL: " + url);
                                Log.d(TAG, "Filename: " + filename);

                                // Background thread дээр download хийх
                                new Thread(() -> {
                                    try {
                                        boolean success = downloadFile(url, filename, cookie);

                                        // Main thread рүү буцааж result өгөх
                                        new Handler(Looper.getMainLooper()).post(() -> {
                                            if (success) {
                                                result.success(true);
                                                Log.d(TAG, "Download success returned to Flutter");
                                            } else {
                                                result.success(false);
                                                Log.e(TAG, "Download failed returned to Flutter");
                                            }
                                        });
                                    } catch (Exception e) {
                                        Log.e(TAG, "Exception in download thread: " + e.getMessage());
                                        e.printStackTrace();

                                        new Handler(Looper.getMainLooper()).post(() -> {
                                            result.error("DOWNLOAD_ERROR", e.getMessage(), null);
                                        });
                                    }
                                }).start();

                            } else {
                                result.notImplemented();
                            }
                        }
                );
    }

    private boolean downloadFile(String url, String filename, String cookie) {
        try {
            Log.d(TAG, "downloadFile() started");

            DownloadManager.Request request = new DownloadManager.Request(Uri.parse(url));

            // Cookie нэмэх
            if (cookie != null && !cookie.isEmpty()) {
                request.addRequestHeader("Cookie", cookie);
                Log.d(TAG, "Cookie added");
            }

            // User-Agent нэмэх
            request.addRequestHeader("User-Agent", "Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36");

            // Title болон description
            request.setTitle(filename);
            request.setDescription("Файл татаж байна...");

            // Notification харуулах
            request.setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED);

            // Destination - Public Downloads folder
            request.setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, filename);

            // Media scanner
            request.allowScanningByMediaScanner();

            // Network types
            request.setAllowedNetworkTypes(
                    DownloadManager.Request.NETWORK_WIFI |
                            DownloadManager.Request.NETWORK_MOBILE
            );

            // Allow roaming
            request.setAllowedOverRoaming(true);

            // DownloadManager руу нэмэх
            DownloadManager downloadManager = (DownloadManager) getSystemService(Context.DOWNLOAD_SERVICE);
            if (downloadManager != null) {
                long downloadId = downloadManager.enqueue(request);
                Log.d(TAG, "Download enqueued with ID: " + downloadId);

                runOnUiThread(() ->
                        Toast.makeText(getApplicationContext(), "Файл татаж эхэллээ...", Toast.LENGTH_SHORT).show()
                );

                return downloadId > 0;
            } else {
                Log.e(TAG, "DownloadManager is null");
            }

            return false;
        } catch (Exception e) {
            Log.e(TAG, "Download error: " + e.getMessage());
            e.printStackTrace();

            runOnUiThread(() ->
                    Toast.makeText(getApplicationContext(), "Алдаа: " + e.getMessage(), Toast.LENGTH_SHORT).show()
            );
            return false;
        }
    }
}