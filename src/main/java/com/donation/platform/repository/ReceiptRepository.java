package com.donation.platform.repository;

import com.donation.platform.entity.Receipt;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

@Repository
public interface ReceiptRepository extends JpaRepository<Receipt, UUID> {
    Optional<Receipt> findByReceiptNumber(String receiptNumber);
    Optional<Receipt> findByDonationId(UUID donationId);
    List<Receipt> findByDonorEmail(String donorEmail);
    boolean existsByDonationId(UUID donationId);
}
