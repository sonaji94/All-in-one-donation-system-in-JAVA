package com.donation.platform.dto;

import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotNull;
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
public class CreateOrderRequest {

    @NotNull(message = "Campaign ID is required")
    private UUID campaignId;

    @NotNull(message = "Donation amount is required")
    @DecimalMin(value = "1.00", message = "Donation amount must be at least 1.00")
    private BigDecimal amount;

    private String donorName;

    @Email(message = "Invalid email format")
    private String donorEmail;

    private String donorPan;

    @Builder.Default
    private Boolean isAnonymous = false;
}
