package com.donation.platform.dto;

import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.math.BigDecimal;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class CreateCampaignRequest {

    @NotBlank(message = "Campaign title is required")
    @Size(min = 5, max = 200, message = "Campaign title must be between 5 and 200 characters")
    private String title;

    @NotBlank(message = "Campaign description is required")
    @Size(min = 20, message = "Campaign description must be at least 20 characters")
    private String description;

    @NotNull(message = "Target amount is required")
    @DecimalMin(value = "100.00", message = "Target amount must be at least 100.00")
    private BigDecimal targetAmount;
}
