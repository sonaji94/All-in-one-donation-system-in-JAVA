package com.donation.platform.controller;

import com.donation.platform.dto.ApiResponse;
import com.donation.platform.entity.Receipt;
import com.donation.platform.service.ReceiptService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.UUID;

@RestController
@RequestMapping("/api/v1/receipts")
@RequiredArgsConstructor
@Slf4j
public class ReceiptController {

    private final ReceiptService receiptService;

    /**
     * Public endpoint to fetch 80G receipt metadata by receipt number.
     */
    @GetMapping("/{receiptNumber}")
    public ResponseEntity<ApiResponse<Receipt>> getReceiptMetadata(@PathVariable String receiptNumber) {
        Receipt receipt = receiptService.getReceiptByNumber(receiptNumber);
        return ResponseEntity.ok(ApiResponse.success(receipt));
    }

    /**
     * Public endpoint to stream the generated 80G PDF receipt as an attachment.
     */
    @GetMapping("/{receiptNumber}/download")
    public ResponseEntity<byte[]> downloadReceiptPdf(@PathVariable String receiptNumber) {
        log.info("Streaming 80G PDF receipt download for: {}", receiptNumber);
        Receipt receipt = receiptService.getReceiptByNumber(receiptNumber);

        byte[] pdfBytes = receipt.getPdfBlob();
        if (pdfBytes == null || pdfBytes.length == 0) {
            return ResponseEntity.notFound().build();
        }

        return ResponseEntity.ok()
                .contentType(MediaType.APPLICATION_PDF)
                .header(HttpHeaders.CONTENT_DISPOSITION, "attachment; filename=\"Tax_Receipt_" + receiptNumber + ".pdf\"")
                .header(HttpHeaders.CACHE_CONTROL, "no-cache, no-store, must-revalidate")
                .body(pdfBytes);
    }

    /**
     * Public endpoint to fetch receipt by donation UUID.
     */
    @GetMapping("/donation/{donationId}")
    public ResponseEntity<ApiResponse<Receipt>> getReceiptByDonationId(@PathVariable UUID donationId) {
        Receipt receipt = receiptService.getReceiptByDonationId(donationId);
        return ResponseEntity.ok(ApiResponse.success(receipt));
    }
}
