package com.donation.platform.event;

import com.donation.platform.entity.Receipt;
import com.donation.platform.service.DonationEmailService;
import com.donation.platform.service.ReceiptService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Component;
import org.springframework.transaction.event.TransactionPhase;
import org.springframework.transaction.event.TransactionalEventListener;

@Component
@RequiredArgsConstructor
@Slf4j
public class DonationEventListener {

    private final ReceiptService receiptService;
    private final DonationEmailService donationEmailService;

    /**
     * Listens for completed donation transactions.
     * TransactionPhase.AFTER_COMMIT guarantees the receipt generation and email dispatch
     * occur ONLY after the donation record has successfully committed to the database.
     */
    @Async
    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    public void onDonationCompleted(DonationCompletedEvent event) {
        log.info("Handling AFTER_COMMIT DonationCompletedEvent for donation ID: {}", event.getDonationId());

        try {
            // 1. Generate and Archive 80G Receipt
            Receipt receipt = receiptService.generateAndSaveReceipt(event.getDonation());

            // 2. Asynchronously Dispatch Email with PDF Attachment
            if (receipt.getPdfBlob() != null && receipt.getPdfBlob().length > 0) {
                donationEmailService.sendDonationReceiptEmail(receipt, receipt.getPdfBlob());
            } else {
                log.warn("Receipt {} has empty PDF blob. Skipping email attachment.", receipt.getReceiptNumber());
            }

        } catch (Exception e) {
            log.error("Failed to complete post-donation receipt workflow for donation ID {}: {}",
                    event.getDonationId(), e.getMessage(), e);
        }
    }
}
