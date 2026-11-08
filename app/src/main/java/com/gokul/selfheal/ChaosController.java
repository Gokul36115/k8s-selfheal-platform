package com.gokul.selfheal;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.net.InetAddress;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

@RestController   // Tells Spring: this class answers web (HTTP) requests
public class ChaosController {

    // Holds on to memory so Java's garbage collector can't free it
    private static final List<byte[]> memoryHog = new ArrayList<>();

    // Normal page: shows which server/container answered
    @GetMapping("/")
    public Map<String, String> home() throws Exception {
        return Map.of(
            "app", "selfheal-app",
            "status", "running",
            "host", InetAddress.getLocalHost().getHostName()
        );
    }

    // Break button 1: returns HTTP 500 (like a production app error)
    @GetMapping("/api/error")
    public ResponseEntity<String> error() {
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body("Simulated HTTP 500 error");
    }

    // Break button 2: very slow response (makes health checks time out)
    @GetMapping("/api/slow")
    public String slow() throws InterruptedException {
        Thread.sleep(15000);   // waits 15 seconds before replying
        return "Responded after 15 seconds";
    }

    // Break button 3: uses up 50 MB of memory on every call
    @GetMapping("/api/memory")
    public String memory() {
        memoryHog.add(new byte[50 * 1024 * 1024]);
        return "Allocated " + (memoryHog.size() * 50) + " MB";
    }

    // Load button: burns CPU for ~ms milliseconds (used to trigger Kubernetes autoscaling)
    @GetMapping("/api/cpu")
    public String cpu(@org.springframework.web.bind.annotation.RequestParam(defaultValue = "200") long ms) {
        long end = System.nanoTime() + Math.min(ms, 2000) * 1_000_000L;
        double x = 0;
        while (System.nanoTime() < end) { x += Math.sqrt(x + 1); }
        return "Burned CPU for " + Math.min(ms, 2000) + " ms (" + (long) x + ")";
    }

    // Break button 4: kills the JVM (like a real crash)
    @GetMapping("/api/crash")
    public String crash() {
        new Thread(() -> {
            try { Thread.sleep(500); } catch (InterruptedException ignored) {}
            Runtime.getRuntime().halt(1);   // exits immediately with code 1
        }).start();
        return "Crashing the JVM in 0.5 seconds...";
    }
}