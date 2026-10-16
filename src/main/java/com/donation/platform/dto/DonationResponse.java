package com.donation.platform.dto;

import com.donation.platform.entity.Donation;
import com.donation.platform.entity.PaymentStatus;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.UUID;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class DonationResponse {
    private UUID id;
    private UUID campaignId;
    private String campaignTitle;
    private BigDecimal amount;
    private String currency;
    private String donorName;
    private PaymentStatus status;
    private String razorpayOrderId;
    private String razorpayPaymentId;
    private LocalDateTime createdAt;

    public static DonationResponse fromEntity(Donation donation) {
        return DonationResponse.builder()
                .id(donation.getId())
                .campaignId(donation.getCampaign().getId())
                .campaignTitle(donation.getCampaign().getTitle())
                .amount(donation.getAmount())
                .currency(donation.getCurrency())
                .donorName(donation.getDonorName() != null ? donation.getDonorName() : "Anonymous")
                .status(donation.getStatus())
                .razorpayOrderId(donation.getRazorpayOrderId())
                .razorpayPaymentId(donation.getRazorpayPaymentId())
                .createdAt(donation.getCreatedAt())
                .build();
    }
}
