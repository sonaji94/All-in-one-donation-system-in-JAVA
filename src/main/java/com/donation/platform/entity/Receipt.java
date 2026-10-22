package com.donation.platform.entity;

import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.CreationTimestamp;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.UUID;

@Entity
@Table(name = "receipts", indexes = {
    @Index(name = "idx_receipt_number", columnList = "receipt_number", unique = true),
    @Index(name = "idx_receipt_donation", columnList = "donation_id", unique = true),
    @Index(name = "idx_receipt_donor_email", columnList = "donor_email")
})
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class Receipt {

    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    @Column(name = "id", updatable = false, nullable = false)
    private UUID id;

    @Column(name = "receipt_number", nullable = false, unique = true, length = 64)
    private String receiptNumber;

    @OneToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "donation_id", nullable = false, unique = true)
    private Donation donation;

    @Column(name = "campaign_title", nullable = false)
    private String campaignTitle;

    @Column(name = "donor_name", nullable = false)
    private String donorName;

    @Column(name = "donor_pan", length = 20)
    private String donorPan;

    @Column(name = "donor_email", nullable = false)
    private String donorEmail;

    @Column(name = "amount", nullable = false, precision = 19, scale = 4)
    private BigDecimal amount;

    @Lob
    @Basic(fetch = FetchType.LAZY)
    @Column(name = "pdf_blob", columnDefinition = "BYTEA")
    private byte[] pdfBlob;

    @CreationTimestamp
    @Column(name = "issued_at", nullable = false, updatable = false)
    private LocalDateTime issuedAt;
}
