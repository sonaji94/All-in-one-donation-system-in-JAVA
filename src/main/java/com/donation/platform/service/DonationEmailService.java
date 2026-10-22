package com.donation.platform.service;

import com.donation.platform.entity.Receipt;
import jakarta.mail.internet.MimeMessage;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.io.ByteArrayResource;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.mail.javamail.MimeMessageHelper;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Service;
import org.thymeleaf.TemplateEngine;
import org.thymeleaf.context.Context;

import java.time.format.DateTimeFormatter;

@Service
@RequiredArgsConstructor
@Slf4j
public class DonationEmailService {

    private final JavaMailSender mailSender;
    private final TemplateEngine templateEngine;

    @Value("${spring.mail.username:donations@impactfund.org}")
    private String fromEmail;

    @Value("${app.organization.name:ImpactFund Humanitarian Foundation}")
    private String orgName;

    private static final DateTimeFormatter DATE_FMT = DateTimeFormatter.ofPattern("dd-MMM-yyyy HH:mm 'IST'");

    /**
     * Dispatches an asynchronous transactional confirmation email containing the 80G tax receipt PDF attachment.
     * Handled on a background thread so the donor's HTTP response is never blocked.
     */
    @Async
    public void sendDonationReceiptEmail(Receipt receipt, byte[] pdfBytes) {
        log.info("Preparing to send 80G receipt email to donor: {} for receipt: {}", 
                receipt.getDonorEmail(), receipt.getReceiptNumber());

        if (receipt.getDonorEmail() == null || receipt.getDonorEmail().isBlank()) {
            log.warn("Donor email is empty. Skipping email dispatch for receipt: {}", receipt.getReceiptNumber());
            return;
        }

        try {
            MimeMessage message = mailSender.createMimeMessage();
            MimeMessageHelper helper = new MimeMessageHelper(message, true, "UTF-8");

            helper.setFrom(fromEmail, orgName);
            helper.setTo(receipt.getDonorEmail());
            helper.setSubject("Donation Receipt & 80G Tax Exemption Certificate - #" + receipt.getReceiptNumber());

            // Build Thymeleaf Context
            Context context = new Context();
            context.setVariable("receiptNumber", receipt.getReceiptNumber());
            context.setVariable("donorName", receipt.getDonorName());
            context.setVariable("campaignTitle", receipt.getCampaignTitle());
            context.setVariable("amount", receipt.getAmount().toPlainString());
            context.setVariable("donorPan", receipt.getDonorPan());
            context.setVariable("paymentId", receipt.getDonation().getRazorpayPaymentId());
            context.setVariable("date", receipt.getIssuedAt().format(DATE_FMT));
            context.setVariable("orgName", orgName);

            String htmlBody;
            try {
                htmlBody = templateEngine.process("email/donation-receipt-email", context);
            } catch (Exception e) {
                log.warn("Thymeleaf template processing failed ({}), falling back to standard HTML", e.getMessage());
                htmlBody = buildFallbackHtml(receipt);
            }

            helper.setText(htmlBody, true);

            // Attach PDF Document
            String filename = "Tax_Receipt_" + receipt.getReceiptNumber() + ".pdf";
            helper.addAttachment(filename, new ByteArrayResource(pdfBytes), "application/pdf");

            mailSender.send(message);
            log.info("Successfully dispatched 80G receipt email to {} with attachment {}", receipt.getDonorEmail(), filename);

        } catch (Exception e) {
            log.error("Failed to send 80G receipt email to {}: {}. PDF remains archived in database.",
                    receipt.getDonorEmail(), e.getMessage());
        }
    }

    private String buildFallbackHtml(Receipt receipt) {
        return "<html><body style='font-family: sans-serif;'>"
                + "<h2>Thank You for Your Donation!</h2>"
                + "<p>Dear " + receipt.getDonorName() + ",</p>"
                + "<p>We gratefully acknowledge your contribution of <strong>INR ₹" + receipt.getAmount() + "</strong> "
                + "towards <strong>" + receipt.getCampaignTitle() + "</strong>.</p>"
                + "<p>Receipt Number: <strong>" + receipt.getReceiptNumber() + "</strong></p>"
                + "<p>Your official Section 80G Income Tax Exemption certificate has been attached as a PDF.</p>"
                + "<br/><p>" + orgName + "</p>"
                + "</body></html>";
    }
}
