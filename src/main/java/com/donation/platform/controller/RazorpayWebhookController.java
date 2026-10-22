package com.donation.platform.controller;

import com.donation.platform.config.RazorpayConfig;
import com.donation.platform.dto.ApiResponse;
import com.donation.platform.service.DonationService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.json.JSONObject;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;

@RestController
@RequestMapping("/api/v1/webhooks")
@RequiredArgsConstructor
@Slf4j
public class RazorpayWebhookController {

    private final DonationService donationService;
    private final RazorpayConfig razorpayConfig;

    /**
     * Razorpay Webhook Endpoint.
     * Receives asynchronous event notifications (e.g., payment.captured, payment.failed).
     * Validates HMAC-SHA256 signature against raw request payload before processing.
     */
    @PostMapping("/razorpay")
    public ResponseEntity<ApiResponse<String>> handleRazorpayWebhook(
            @RequestBody String rawPayload,
            @RequestHeader(value = "X-Razorpay-Signature", required = false) String razorpaySignature) {

        log.info("Received Razorpay Webhook notification. Signature present: {}", razorpaySignature != null);

        if (razorpaySignature == null || razorpaySignature.isBlank()) {
            log.warn("Rejected webhook request: Missing 'X-Razorpay-Signature' header.");
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                    .body(ApiResponse.error("Missing webhook signature header"));
        }

        // Cryptographically verify signature using configured webhook secret
        boolean isValidSignature = verifyHmacSha256(rawPayload, razorpaySignature, razorpayConfig.getWebhookSecret());
        if (!isValidSignature) {
            log.error("Rejected webhook request: Invalid cryptographic HMAC signature. Possible forgery attempt!");
            return ResponseEntity.status(HttpStatus.BAD_REQUEST)
                    .body(ApiResponse.error("Invalid webhook signature verification failed"));
        }

        try {
            JSONObject root = new JSONObject(rawPayload);
            String eventType = root.optString("event");
            log.info("Processing verified Razorpay webhook event: '{}'", eventType);

            JSONObject payloadObj = root.optJSONObject("payload");
            if (payloadObj == null) {
                return ResponseEntity.ok(ApiResponse.success("Ignored: Empty webhook payload object", null));
            }

            JSONObject paymentObj = payloadObj.optJSONObject("payment");
            if (paymentObj == null) {
                return ResponseEntity.ok(ApiResponse.success("Ignored: Non-payment event", null));
            }

            JSONObject paymentEntity = paymentObj.optJSONObject("entity");
            if (paymentEntity == null) {
                return ResponseEntity.ok(ApiResponse.success("Ignored: No payment entity found", null));
            }

            String paymentId = paymentEntity.optString("id");
            String orderId = paymentEntity.optString("order_id");

            if (orderId == null || orderId.isBlank()) {
                log.warn("Payment entity {} contains no associated order_id. Skipping reconciliation.", paymentId);
                return ResponseEntity.ok(ApiResponse.success("Skipped: No order_id present", null));
            }

            switch (eventType) {
                case "payment.captured":
                    log.info("Reconciling payment.captured for Order ID: {}, Payment ID: {}", orderId, paymentId);
                    donationService.reconcilePaymentCaptured(orderId, paymentId, razorpaySignature);
                    break;

                case "payment.failed":
                    String errorDesc = paymentEntity.optString("error_description", "Payment transaction failed");
                    log.warn("Reconciling payment.failed for Order ID: {}, Payment ID: {}. Reason: {}", orderId, paymentId, errorDesc);
                    donationService.reconcilePaymentFailed(orderId, paymentId, errorDesc);
                    break;

                default:
                    log.info("Unhandled webhook event type '{}' acknowledged safely without action.", eventType);
                    break;
            }

            return ResponseEntity.ok(ApiResponse.success("Webhook processed successfully", null));

        } catch (Exception ex) {
            log.error("Unexpected error processing Razorpay webhook payload: {}", ex.getMessage(), ex);
            // Return 200 OK or 500 depending on retry semantics (200 prevents Razorpay storm loops on non-retryable bugs)
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(ApiResponse.error("Webhook processing error: " + ex.getMessage()));
        }
    }

    /**
     * Constant-time HMAC-SHA256 signature verification.
     * Prevents timing attack vulnerabilities during cryptographic verification.
     */
    private boolean verifyHmacSha256(String data, String signature, String secret) {
        if (data == null || signature == null || secret == null) {
            return false;
        }

        try {
            Mac sha256Hmac = Mac.getInstance("HmacSHA256");
            SecretKeySpec secretKey = new SecretKeySpec(secret.getBytes(StandardCharsets.UTF_8), "HmacSHA256");
            sha256Hmac.init(secretKey);

            byte[] hashBytes = sha256Hmac.doFinal(data.getBytes(StandardCharsets.UTF_8));
            StringBuilder hexStringBuilder = new StringBuilder();
            for (byte b : hashBytes) {
                String hex = Integer.toHexString(0xff & b);
                if (hex.length() == 1) {
                    hexStringBuilder.append('0');
                }
                hexStringBuilder.append(hex);
            }

            String computedSignature = hexStringBuilder.toString();

            // Constant-time comparison
            return MessageDigest.isEqual(
                    computedSignature.getBytes(StandardCharsets.UTF_8),
                    signature.getBytes(StandardCharsets.UTF_8)
            );

        } catch (Exception e) {
            log.error("Cryptographic HMAC calculation failed: {}", e.getMessage());
            return false;
        }
    }
}
