package com.donation.platform.controller;

import com.donation.platform.dto.ApiResponse;
import com.donation.platform.dto.CreateOrderRequest;
import com.donation.platform.dto.CreateOrderResponse;
import com.donation.platform.dto.DonationResponse;
import com.donation.platform.dto.PaymentVerificationRequest;
import com.donation.platform.entity.User;
import com.donation.platform.service.DonationService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.UUID;

@RestController
@RequestMapping("/api/v1/donations")
@RequiredArgsConstructor
@Slf4j
public class DonationController {

    private final DonationService donationService;

    /**
     * Public endpoint to initiate a Razorpay order.
     * Can be invoked by guests (anonymous) or logged-in users.
     */
    @PostMapping("/order")
    public ResponseEntity<ApiResponse<CreateOrderResponse>> createOrder(
            @Valid @RequestBody CreateOrderRequest request,
            @AuthenticationPrincipal User authenticatedUser) {

        log.info("Received request to initiate order for campaign: {}", request.getCampaignId());
        CreateOrderResponse response = donationService.createDonationOrder(request, authenticatedUser);
        return ResponseEntity.status(HttpStatus.CREATED)
                .body(ApiResponse.success("Payment order created successfully", response));
    }

    /**
     * Public endpoint to verify Razorpay HMAC signature after donor checkout.
     * Captures payment, transitions donation to SUCCESS, and atomically updates campaign funding.
     */
    @PostMapping("/verify")
    public ResponseEntity<ApiResponse<DonationResponse>> verifyPayment(
            @Valid @RequestBody PaymentVerificationRequest request) {

        log.info("Received payment verification callback for order: {}", request.getRazorpayOrderId());
        DonationResponse response = donationService.verifyAndCapturePayment(request);
        return ResponseEntity.ok(ApiResponse.success("Payment verified and donation captured successfully", response));
    }

    /**
     * Public endpoint to list verified donations for a specific campaign.
     */
    @GetMapping("/campaign/{campaignId}")
    public ResponseEntity<ApiResponse<List<DonationResponse>>> getDonationsByCampaign(
            @PathVariable UUID campaignId) {

        List<DonationResponse> donations = donationService.getDonationsByCampaign(campaignId);
        return ResponseEntity.ok(ApiResponse.success(donations));
    }
}
