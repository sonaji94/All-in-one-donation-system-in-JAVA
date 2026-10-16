package com.donation.platform.controller;

import com.donation.platform.dto.ApiResponse;
import com.donation.platform.dto.CampaignResponse;
import com.donation.platform.dto.CreateCampaignRequest;
import com.donation.platform.entity.User;
import com.donation.platform.service.CampaignService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Sort;
import org.springframework.data.web.PageableDefault;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.UUID;

@RestController
@RequestMapping("/api/v1/campaigns")
@RequiredArgsConstructor
@Slf4j
public class CampaignController {

    private final CampaignService campaignService;

    /**
     * Public endpoint to list active campaigns.
     * Supports pagination and returns real-time collected funds and percentage.
     */
    @GetMapping
    public ResponseEntity<ApiResponse<List<CampaignResponse>>> getActiveCampaigns() {
        List<CampaignResponse> campaigns = campaignService.getActiveCampaigns();
        return ResponseEntity.ok(ApiResponse.success(campaigns));
    }

    /**
     * Public endpoint to get paginated active campaigns.
     */
    @GetMapping("/paged")
    public ResponseEntity<ApiResponse<Page<CampaignResponse>>> getActiveCampaignsPaged(
            @PageableDefault(size = 10, sort = "createdAt", direction = Sort.Direction.DESC) Pageable pageable) {
        Page<CampaignResponse> page = campaignService.getActiveCampaignsPaged(pageable);
        return ResponseEntity.ok(ApiResponse.success(page));
    }

    /**
     * Public endpoint to get specific campaign details by ID.
     */
    @GetMapping("/{id}")
    public ResponseEntity<ApiResponse<CampaignResponse>> getCampaignById(@PathVariable UUID id) {
        CampaignResponse campaign = campaignService.getCampaignById(id);
        return ResponseEntity.ok(ApiResponse.success(campaign));
    }

    /**
     * Authenticated endpoint to create a new campaign.
     * The authenticated user is registered as the campaign owner.
     */
    @PostMapping
    public ResponseEntity<ApiResponse<CampaignResponse>> createCampaign(
            @Valid @RequestBody CreateCampaignRequest request,
            @AuthenticationPrincipal User authenticatedUser) {

        log.info("Creating campaign '{}' for user: {}", request.getTitle(), authenticatedUser.getEmail());
        CampaignResponse response = campaignService.createCampaign(request, authenticatedUser);
        return ResponseEntity.status(HttpStatus.CREATED)
                .body(ApiResponse.success("Campaign created successfully", response));
    }
}
