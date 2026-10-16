package com.donation.platform.dto;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.math.BigDecimal;
import java.util.UUID;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class CreateOrderResponse {
    private String razorpayOrderId;
    private BigDecimal amount;
    private String currency;
    private String keyId;
    private UUID donationId;
}
