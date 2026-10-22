package com.donation.platform.service;

import com.donation.platform.config.RazorpayConfig;
import com.donation.platform.dto.CreateOrderRequest;
import com.donation.platform.dto.CreateOrderResponse;
import com.donation.platform.dto.DonationResponse;
import com.donation.platform.dto.PaymentVerificationRequest;
import com.donation.platform.entity.*;
import com.donation.platform.exception.InvalidCampaignException;
import com.donation.platform.exception.PaymentVerificationException;
import com.donation.platform.exception.ResourceNotFoundException;
import com.donation.platform.repository.CampaignRepository;
import com.donation.platform.repository.DonationRepository;
import com.razorpay.Order;
import com.razorpay.RazorpayClient;
import com.razorpay.RazorpayException;
import com.razorpay.Utils;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.json.JSONObject;
import com.donation.platform.event.DonationCompletedEvent;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.orm.ObjectOptimisticLockingFailureException;
import org.springframework.retry.annotation.Backoff;
import org.springframework.retry.annotation.Retryable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Isolation;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.util.List;
import java.util.UUID;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
@Slf4j
public class DonationService {

    private final RazorpayClient razorpayClient;
    private final RazorpayConfig razorpayConfig;
    private final CampaignRepository campaignRepository;
    private final DonationRepository donationRepository;
    private final ApplicationEventPublisher eventPublisher;

    /**
     * Creates an order via Razorpay API, records initial INITIATED state in DB,
     * and returns the order checkout payload for frontend invocation.
     */
    @Transactional
    public CreateOrderResponse createDonationOrder(CreateOrderRequest request, User authenticatedUser) {
        log.info("Initiating donation order for campaign ID: {}, amount: {}", request.getCampaignId(), request.getAmount());

        Campaign campaign = campaignRepository.findById(request.getCampaignId())
                .orElseThrow(() -> new ResourceNotFoundException("Campaign not found with ID: " + request.getCampaignId()));

        if (campaign.getStatus() != CampaignStatus.ACTIVE) {
            throw new InvalidCampaignException("Cannot donate to a campaign that is " + campaign.getStatus());
        }

        // Razorpay expects amount in smallest currency unit (paise for INR: 1 INR = 100 paise)
        long amountInPaise = request.getAmount().multiply(BigDecimal.valueOf(100)).longValue();

        String receipt = "rcpt_" + System.currentTimeMillis();

        JSONObject orderRequest = new JSONObject();
        orderRequest.put("amount", amountInPaise);
        orderRequest.put("currency", "INR");
        orderRequest.put("receipt", receipt);

        JSONObject notes = new JSONObject();
        notes.put("campaignId", campaign.getId().toString());
        notes.put("campaignTitle", campaign.getTitle());
        orderRequest.put("notes", notes);

        Order razorpayOrder;
        try {
            razorpayOrder = razorpayClient.orders.create(orderRequest);
        } catch (RazorpayException e) {
            log.error("Razorpay order creation failed: {}", e.getMessage(), e);
            throw new PaymentVerificationException("Failed to initiate order with Razorpay: " + e.getMessage(), e);
        }

        String razorpayOrderId = razorpayOrder.get("id");

        // Determine donor details based on anonymity flag and authentication
        User donor = Boolean.TRUE.equals(request.getIsAnonymous()) ? null : authenticatedUser;
        String donorName = Boolean.TRUE.equals(request.getIsAnonymous())
                ? "Anonymous"
                : (request.getDonorName() != null && !request.getDonorName().isBlank()
                        ? request.getDonorName()
                        : (authenticatedUser != null ? authenticatedUser.getName() : "Anonymous"));

        String donorEmail = Boolean.TRUE.equals(request.getIsAnonymous())
                ? null
                : (request.getDonorEmail() != null && !request.getDonorEmail().isBlank()
                        ? request.getDonorEmail()
                        : (authenticatedUser != null ? authenticatedUser.getEmail() : null));

        Donation donation = Donation.builder()
                .campaign(campaign)
                .donor(donor)
                .donorName(donorName)
                .donorEmail(donorEmail)
                .donorPan(request.getDonorPan() != null && !request.getDonorPan().isBlank() ? request.getDonorPan().toUpperCase().trim() : null)
                .amount(request.getAmount())
                .currency("INR")
                .razorpayOrderId(razorpayOrderId)
                .status(PaymentStatus.INITIATED)
                .build();

        donationRepository.save(donation);

        log.info("Donation initiated successfully. DB ID: {}, Razorpay Order ID: {}", donation.getId(), razorpayOrderId);

        return CreateOrderResponse.builder()
                .razorpayOrderId(razorpayOrderId)
                .amount(request.getAmount())
                .currency("INR")
                .keyId(razorpayConfig.getKeyId())
                .donationId(donation.getId())
                .build();
    }

    /**
     * Verifies the cryptographic HMAC-SHA256 signature returned by Razorpay checkout,
     * atomically updates the campaign's collectedAmount under optimistic locking,
     * and transitions donation state to SUCCESS.
     * Retries automatically if optimistic lock collision occurs under concurrent donations.
     */
    @Retryable(
            retryFor = {ObjectOptimisticLockingFailureException.class},
            maxAttempts = 5,
            backoff = @Backoff(delay = 100, multiplier = 2)
    )
    @Transactional(isolation = Isolation.READ_COMMITTED)
    public DonationResponse verifyAndCapturePayment(PaymentVerificationRequest request) {
        log.info("Verifying payment for Razorpay Order ID: {}", request.getRazorpayOrderId());

        Donation donation = donationRepository.findByRazorpayOrderId(request.getRazorpayOrderId())
                .orElseThrow(() -> new ResourceNotFoundException("Donation record not found for Razorpay Order ID: " + request.getRazorpayOrderId()));

        // Idempotency check: if payment already successfully processed, return existing record
        if (donation.getStatus() == PaymentStatus.SUCCESS) {
            log.info("Donation for order {} has already been successfully captured. Returning cached state.", request.getRazorpayOrderId());
            return DonationResponse.fromEntity(donation);
        }

        // Construct attributes map for Razorpay cryptographic verification
        JSONObject attributes = new JSONObject();
        attributes.put("razorpay_order_id", request.getRazorpayOrderId());
        attributes.put("razorpay_payment_id", request.getRazorpayPaymentId());
        attributes.put("razorpay_signature", request.getRazorpaySignature());

        boolean isSignatureValid = false;
        try {
            isSignatureValid = Utils.verifyPaymentSignature(attributes, razorpayConfig.getKeySecret());
        } catch (RazorpayException e) {
            log.error("Razorpay signature verification exception: {}", e.getMessage(), e);
            isSignatureValid = false;
        }

        if (!isSignatureValid) {
            log.warn("Payment verification failed for order: {}. Marking donation FAILED.", request.getRazorpayOrderId());
            donation.setStatus(PaymentStatus.FAILED);
            donation.setRazorpayPaymentId(request.getRazorpayPaymentId());
            donation.setRazorpaySignature(request.getRazorpaySignature());
            donationRepository.save(donation);

            throw new PaymentVerificationException("Invalid payment signature. Payment verification failed.");
        }

        // Signature is valid: Transition donation to SUCCESS
        donation.setStatus(PaymentStatus.SUCCESS);
        donation.setRazorpayPaymentId(request.getRazorpayPaymentId());
        donation.setRazorpaySignature(request.getRazorpaySignature());
        donationRepository.save(donation);

        // Atomically update campaign collectedAmount
        // Optimistic locking via @Version ensures consistency when multiple concurrent donations succeed simultaneously
        Campaign campaign = campaignRepository.findById(donation.getCampaign().getId())
                .orElseThrow(() -> new ResourceNotFoundException("Campaign not found with ID: " + donation.getCampaign().getId()));

        BigDecimal newCollected = campaign.getCollectedAmount().add(donation.getAmount());
        campaign.setCollectedAmount(newCollected);

        // If target reached, update status to COMPLETED
        if (campaign.getTargetAmount() != null && newCollected.compareTo(campaign.getTargetAmount()) >= 0) {
            campaign.setStatus(CampaignStatus.COMPLETED);
            log.info("Campaign {} has achieved its target funding goal!", campaign.getId());
        }

        campaignRepository.save(campaign);

        log.info("Payment verified and captured successfully for donation ID: {}. Campaign new total: {}",
                donation.getId(), newCollected);

        // Emit AFTER_COMMIT event for 80G receipt generation and email dispatch
        eventPublisher.publishEvent(new DonationCompletedEvent(this, donation));

        return DonationResponse.fromEntity(donation);
    }

    /**
     * Fallback reconciliation executed by Razorpay Webhook (payment.captured event).
     * Guarantees that if a donor closes their browser before frontend verification executes,
     * the donation is transitioned to SUCCESS, campaign funds are updated, and 80G receipt is dispatched.
     * Fully idempotent: If already SUCCESS, skips duplicate funding increment.
     */
    @Retryable(
            retryFor = {ObjectOptimisticLockingFailureException.class},
            maxAttempts = 5,
            backoff = @Backoff(delay = 100, multiplier = 2)
    )
    @Transactional(isolation = Isolation.READ_COMMITTED)
    public DonationResponse reconcilePaymentCaptured(String razorpayOrderId, String razorpayPaymentId, String razorpaySignature) {
        log.info("Executing webhook reconciliation for Razorpay Order ID: {}, Payment ID: {}", razorpayOrderId, razorpayPaymentId);

        Donation donation = donationRepository.findByRazorpayOrderId(razorpayOrderId)
                .orElseThrow(() -> new ResourceNotFoundException("Donation record not found for Order ID: " + razorpayOrderId));

        if (donation.getStatus() == PaymentStatus.SUCCESS) {
            log.info("Donation {} already captured and reconciled. Idempotent webhook skip.", razorpayOrderId);
            return DonationResponse.fromEntity(donation);
        }

        donation.setStatus(PaymentStatus.SUCCESS);
        donation.setRazorpayPaymentId(razorpayPaymentId);
        if (razorpaySignature != null) {
            donation.setRazorpaySignature(razorpaySignature);
        }
        donationRepository.save(donation);

        // Atomically update campaign with optimistic locking
        Campaign campaign = campaignRepository.findById(donation.getCampaign().getId())
                .orElseThrow(() -> new ResourceNotFoundException("Campaign not found with ID: " + donation.getCampaign().getId()));

        BigDecimal newCollected = campaign.getCollectedAmount().add(donation.getAmount());
        campaign.setCollectedAmount(newCollected);

        if (campaign.getTargetAmount() != null && newCollected.compareTo(campaign.getTargetAmount()) >= 0) {
            campaign.setStatus(CampaignStatus.COMPLETED);
        }
        campaignRepository.save(campaign);

        log.info("Webhook successfully reconciled donation {}. Emitting DonationCompletedEvent.", donation.getId());
        eventPublisher.publishEvent(new DonationCompletedEvent(this, donation));

        return DonationResponse.fromEntity(donation);
    }

    /**
     * Webhook reconciliation for failed payments (payment.failed event).
     */
    @Transactional
    public void reconcilePaymentFailed(String razorpayOrderId, String razorpayPaymentId, String errorDescription) {
        log.warn("Reconciling payment failure for Order ID: {}, Payment ID: {}. Reason: {}", 
                razorpayOrderId, razorpayPaymentId, errorDescription);

        donationRepository.findByRazorpayOrderId(razorpayOrderId).ifPresent(donation -> {
            if (donation.getStatus() != PaymentStatus.SUCCESS) {
                donation.setStatus(PaymentStatus.FAILED);
                donation.setRazorpayPaymentId(razorpayPaymentId);
                donationRepository.save(donation);
                log.info("Updated donation {} status to FAILED via webhook reconciliation", donation.getId());
            }
        });
    }

    @Transactional(readOnly = true)
    public List<DonationResponse> getDonationsByCampaign(UUID campaignId) {
        return donationRepository.findByCampaignId(campaignId).stream()
                .map(DonationResponse::fromEntity)
                .collect(Collectors.toList());
    }

    @Transactional(readOnly = true)
    public List<DonationResponse> getDonationsByDonor(UUID donorId) {
        return donationRepository.findByDonorId(donorId).stream()
                .map(DonationResponse::fromEntity)
                .collect(Collectors.toList());
    }
}
