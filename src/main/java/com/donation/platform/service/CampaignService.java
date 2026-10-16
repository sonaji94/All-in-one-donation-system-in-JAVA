package com.donation.platform.service;

import com.donation.platform.dto.CampaignResponse;
import com.donation.platform.dto.CreateCampaignRequest;
import com.donation.platform.entity.Campaign;
import com.donation.platform.entity.CampaignStatus;
import com.donation.platform.entity.User;
import com.donation.platform.exception.ResourceNotFoundException;
import com.donation.platform.repository.CampaignRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.util.List;
import java.util.UUID;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
@Slf4j
public class CampaignService {

    private final CampaignRepository campaignRepository;

    @Transactional
    public CampaignResponse createCampaign(CreateCampaignRequest request, User owner) {
        log.info("Creating new campaign: '{}' by owner ID: {}", request.getTitle(), owner.getId());

        Campaign campaign = Campaign.builder()
                .title(request.getTitle())
                .description(request.getDescription())
                .targetAmount(request.getTargetAmount())
                .collectedAmount(BigDecimal.ZERO)
                .status(CampaignStatus.ACTIVE)
                .owner(owner)
                .build();

        Campaign saved = campaignRepository.save(campaign);
        return CampaignResponse.fromEntity(saved);
    }

    @Transactional(readOnly = true)
    public List<CampaignResponse> getActiveCampaigns() {
        return campaignRepository.findByStatus(CampaignStatus.ACTIVE).stream()
                .map(CampaignResponse::fromEntity)
                .collect(Collectors.toList());
    }

    @Transactional(readOnly = true)
    public Page<CampaignResponse> getActiveCampaignsPaged(Pageable pageable) {
        return campaignRepository.findByStatus(CampaignStatus.ACTIVE, pageable)
                .map(CampaignResponse::fromEntity);
    }

    @Transactional(readOnly = true)
    public CampaignResponse getCampaignById(UUID id) {
        Campaign campaign = campaignRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Campaign not found with ID: " + id));
        return CampaignResponse.fromEntity(campaign);
    }

    @Transactional(readOnly = true)
    public List<CampaignResponse> getCampaignsByOwner(UUID ownerId) {
        return campaignRepository.findByOwnerId(ownerId).stream()
                .map(CampaignResponse::fromEntity)
                .collect(Collectors.toList());
    }
}
