package com.donation.platform.repository;

import com.donation.platform.entity.Campaign;
import com.donation.platform.entity.CampaignStatus;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.UUID;

@Repository
public interface CampaignRepository extends JpaRepository<Campaign, UUID> {
    List<Campaign> findByStatus(CampaignStatus status);
    Page<Campaign> findByStatus(CampaignStatus status, Pageable pageable);
    List<Campaign> findByOwnerId(UUID ownerId);
}
