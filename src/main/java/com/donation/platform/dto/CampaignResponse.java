package com.donation.platform.dto;

import com.donation.platform.entity.Campaign;
import com.donation.platform.entity.CampaignStatus;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDateTime;
import java.util.UUID;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class CampaignResponse {
    private UUID id;
    private String title;
    private String description;
    private BigDecimal targetAmount;
    private BigDecimal collectedAmount;
    private Double percentageFunded;
    private CampaignStatus status;
    private UUID ownerId;
    private String ownerName;
    private LocalDateTime createdAt;

    public static CampaignResponse fromEntity(Campaign campaign) {
        Double percentage = 0.0;
        if (campaign.getTargetAmount() != null && campaign.getTargetAmount().compareTo(BigDecimal.ZERO) > 0) {
            percentage = campaign.getCollectedAmount()
                    .multiply(BigDecimal.valueOf(100))
                    .divide(campaign.getTargetAmount(), 2, RoundingMode.HALF_UP)
                    .doubleValue();
        }

        return CampaignResponse.builder()
                .id(campaign.getId())
                .title(campaign.getTitle())
                .description(campaign.getDescription())
                .targetAmount(campaign.getTargetAmount())
                .collectedAmount(campaign.getCollectedAmount())
                .percentageFunded(percentage)
                .status(campaign.getStatus())
                .ownerId(campaign.getOwner() != null ? campaign.getOwner().getId() : null)
                .ownerName(campaign.getOwner() != null ? campaign.getOwner().getName() : "Unknown")
                .createdAt(campaign.getCreatedAt())
                .build();
    }
}
