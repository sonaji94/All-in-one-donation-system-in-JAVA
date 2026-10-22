package com.donation.platform.service;

import com.donation.platform.entity.Donation;
import com.donation.platform.entity.Receipt;
import com.donation.platform.exception.ResourceNotFoundException;
import com.donation.platform.repository.ReceiptRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.util.Optional;
import java.util.UUID;
import java.util.concurrent.ThreadLocalRandom;

@Service
@RequiredArgsConstructor
@Slf4j
public class ReceiptService {

    private final ReceiptRepository receiptRepository;
    private final ReceiptPdfService receiptPdfService;

    private static final DateTimeFormatter DATE_CODE_FMT = DateTimeFormatter.ofPattern("yyyyMMdd");

    /**
     * Generates and archives an 80G tax receipt for a successfully captured donation.
     * Idempotent: If a receipt already exists for this donation, it returns the existing record.
     */
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public Receipt generateAndSaveReceipt(Donation donation) {
        log.info("Processing receipt issuance for donation ID: {}", donation.getId());

        // Idempotency: Return existing receipt if already issued
        Optional<Receipt> existing = receiptRepository.findByDonationId(donation.getId());
        if (existing.isPresent()) {
            log.info("Receipt already exists for donation ID: {}. Receipt Number: {}", 
                    donation.getId(), existing.get().getReceiptNumber());
            return existing.get();
        }

        String receiptNumber = generateReceiptNumber();

        Receipt receipt = Receipt.builder()
                .receiptNumber(receiptNumber)
                .donation(donation)
                .campaignTitle(donation.getCampaign().getTitle())
                .donorName(donation.getDonorName() != null ? donation.getDonorName() : "Generous Donor")
                .donorPan(donation.getDonorPan())
                .donorEmail(donation.getDonorEmail() != null ? donation.getDonorEmail() : "")
                .amount(donation.getAmount())
                .build();

        // Generate PDF Bytes
        byte[] pdfBytes = receiptPdfService.generate80GReceiptPdf(receipt, donation);
        receipt.setPdfBlob(pdfBytes);

        Receipt savedReceipt = receiptRepository.save(receipt);
        log.info("Saved 80G tax receipt {} for donation ID: {}", receiptNumber, donation.getId());
        return savedReceipt;
    }

    @Transactional(readOnly = true)
    public Receipt getReceiptByNumber(String receiptNumber) {
        return receiptRepository.findByReceiptNumber(receiptNumber)
                .orElseThrow(() -> new ResourceNotFoundException("Receipt not found with number: " + receiptNumber));
    }

    @Transactional(readOnly = true)
    public Receipt getReceiptByDonationId(UUID donationId) {
        return receiptRepository.findByDonationId(donationId)
                .orElseThrow(() -> new ResourceNotFoundException("Receipt not found for donation ID: " + donationId));
    }

    private String generateReceiptNumber() {
        String datePart = LocalDate.now().format(DATE_CODE_FMT);
        int randomCode = ThreadLocalRandom.current().nextInt(1000, 9999);
        return String.format("REC-%s-%04d", datePart, randomCode);
    }
}
