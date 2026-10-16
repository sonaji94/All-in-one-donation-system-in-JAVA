package com.donation.platform.repository;

import com.donation.platform.entity.Donation;
import com.donation.platform.entity.PaymentStatus;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

@Repository
public interface DonationRepository extends JpaRepository<Donation, UUID> {
    Optional<Donation> findByRazorpayOrderId(String orderId);
    List<Donation> findByCampaignId(UUID campaignId);
    List<Donation> findByCampaignIdAndStatus(UUID campaignId, PaymentStatus status);
    List<Donation> findByDonorId(UUID donorId);
}
